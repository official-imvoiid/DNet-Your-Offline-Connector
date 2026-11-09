//! The PC's camera, for reading a code off someone's screen.
//!
//! Pictures are kept in memory only, and only the newest: each replaces
//! the last, and the last goes when the camera stops. Nothing is written
//! to disk, so no picture of the user can end up in a synced folder. The
//! app takes the newest picture with [`dnet_radio_frame`](crate::dnet_radio_frame),
//! shows it to aim with and looks for a code in it.
//!
//! The camera is opened shared and read-only, so it is not taken away from
//! another app that is using it.
//!
//! Not yet verified on devices.

use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use windows::core::Result;
use windows::Devices::Enumeration::{DeviceClass, DeviceInformation};
use windows::Foundation::TypedEventHandler;
use windows::Graphics::Imaging::{BitmapAlphaMode, BitmapPixelFormat, SoftwareBitmap};
use windows::Media::Capture::Frames::{
    MediaFrameArrivedEventArgs, MediaFrameReader, MediaFrameReaderStartStatus, MediaFrameSourceKind,
};
use windows::Media::Capture::{
    MediaCapture, MediaCaptureInitializationSettings, MediaCaptureMemoryPreference, MediaCaptureSharingMode,
    StreamingCaptureMode,
};
use windows::Media::MediaProperties::MediaEncodingSubtypes;
use windows::Storage::Streams::{Buffer, DataReader};

use crate::lock;

/// The widest picture kept. Enough to read a code across a desk; small
/// enough to look through several times a second.
const MAX_WIDTH: u32 = 800;
/// The most pictures a second worth keeping.
const EVERY: Duration = Duration::from_millis(60);

struct Camera {
    /// Which opening of the camera this is. One that was stopped must not
    /// speak for the next.
    turn: u32,
    /// "off", "starting", "on", or why it is not on: "denied" (Windows does
    /// not let desktop apps use the camera), "none" (no camera) or
    /// "failed" (in use only by another app, or it would not start).
    state: &'static str,
    stop: Option<Sender<()>>,
}

static CAMERA: Mutex<Camera> = Mutex::new(Camera { turn: 0, state: "off", stop: None });

/// The newest picture: width, height, BGRA pixels, and a number that goes
/// up with each one.
pub struct Frame {
    pub width: u32,
    pub height: u32,
    pub seq: u64,
    pub pixels: Vec<u8>,
}

pub static FRAME: Mutex<Option<Frame>> = Mutex::new(None);

/// How many cameras Windows knows of.
pub fn count() -> u32 {
    DeviceInformation::FindAllAsyncDeviceClass(DeviceClass::VideoCapture)
        .and_then(|finding| finding.join())
        .and_then(|all| all.Size())
        .unwrap_or(0)
}

/// Starts the camera. Whether it worked shows in [`state`] a moment later.
pub fn start() {
    stop();
    let (tell, told) = channel();
    let turn = {
        let mut camera = lock(&CAMERA);
        camera.turn += 1;
        camera.state = "starting";
        camera.stop = Some(tell);
        camera.turn
    };
    thread::spawn(move || {
        if let Err(error) = hold(turn, told) {
            let why = match error.code().0 as u32 {
                // E_ACCESSDENIED: camera access is off for desktop apps.
                0x8007_0005 => "denied",
                // MF_E_NO_CAPTURE_DEVICES_AVAILABLE.
                0xC00D_36D5 => "none",
                _ => "failed",
            };
            set(turn, why);
        }
    });
}

/// Stops the camera, if it is on, and forgets the last picture.
pub fn stop() {
    let mut camera = lock(&CAMERA);
    camera.turn += 1;
    camera.state = "off";
    if let Some(stop) = camera.stop.take() {
        let _ = stop.send(());
    }
    drop(camera);
    *lock(&FRAME) = None;
}

pub fn state() -> Value {
    json!({ "state": lock(&CAMERA).state })
}

fn set(turn: u32, state: &'static str) {
    let mut camera = lock(&CAMERA);
    if camera.turn == turn {
        camera.state = state;
        if state != "on" && state != "starting" {
            camera.stop = None;
        }
    }
}

/// Opens the camera and keeps the newest picture until told to stop.
fn hold(turn: u32, told: Receiver<()>) -> Result<()> {
    let settings = MediaCaptureInitializationSettings::new()?;
    settings.SetStreamingCaptureMode(StreamingCaptureMode::Video)?;
    settings.SetMemoryPreference(MediaCaptureMemoryPreference::Cpu)?;
    settings.SetSharingMode(MediaCaptureSharingMode::SharedReadOnly)?;
    let capture = MediaCapture::new()?;
    capture.InitializeWithSettingsAsync(&settings)?.join()?;

    let mut colour = None;
    for pair in capture.FrameSources()? {
        let source = pair.Value()?;
        if source.Info()?.SourceKind()? == MediaFrameSourceKind::Color {
            colour = Some(source);
            break;
        }
    }
    let Some(source) = colour else {
        set(turn, "none");
        return Ok(());
    };
    let reader = capture
        .CreateFrameReaderWithSubtypeAsync(&source, &MediaEncodingSubtypes::Bgra8()?)?
        .join()?;
    let last = Mutex::new(Instant::now() - EVERY);
    reader.FrameArrived(&TypedEventHandler::<MediaFrameReader, MediaFrameArrivedEventArgs>::new(
        move |reader, _| {
            {
                let mut last = lock(&last);
                if last.elapsed() < EVERY {
                    return Ok(());
                }
                *last = Instant::now();
            }
            let reader = reader.ok()?;
            let Ok(frame) = reader.TryAcquireLatestFrame() else {
                return Ok(());
            };
            let bitmap = frame.VideoMediaFrame()?.SoftwareBitmap()?;
            keep(turn, &bitmap)
        },
    ))?;
    if reader.StartAsync()?.join()? != MediaFrameReaderStartStatus::Success {
        set(turn, "failed");
        return Ok(());
    }
    set(turn, "on");

    // Until told to stop, or until there is nobody left to tell it.
    let _ = told.recv();
    let _ = reader.StopAsync().and_then(|stopping| stopping.join());
    let _ = reader.Close();
    let _ = capture.Close();
    Ok(())
}

/// Copies one picture into [`FRAME`], made smaller if it is wide.
fn keep(turn: u32, bitmap: &SoftwareBitmap) -> Result<()> {
    let bitmap = if bitmap.BitmapPixelFormat()? == BitmapPixelFormat::Bgra8 {
        bitmap.clone()
    } else {
        SoftwareBitmap::ConvertWithAlpha(bitmap, BitmapPixelFormat::Bgra8, BitmapAlphaMode::Ignore)?
    };
    let (Ok(width), Ok(height)) = (u32::try_from(bitmap.PixelWidth()?), u32::try_from(bitmap.PixelHeight()?)) else {
        return Ok(());
    };
    if width == 0 || height == 0 {
        return Ok(());
    }
    let size = width * height * 4;
    let buffer = Buffer::Create(size)?;
    bitmap.CopyToBuffer(&buffer)?;
    let mut full = vec![0u8; buffer.Length()?.min(size) as usize];
    DataReader::FromBuffer(&buffer)?.ReadBytes(&mut full)?;
    if full.len() < size as usize {
        return Ok(());
    }
    let (pixels, width, height) = shrink(&full, width, height);
    // A picture from a camera that has since been stopped is not kept.
    if lock(&CAMERA).turn != turn {
        return Ok(());
    }
    let mut kept = lock(&FRAME);
    let seq = kept.as_ref().map_or(0, |frame| frame.seq) + 1;
    *kept = Some(Frame { width, height, seq, pixels });
    Ok(())
}

/// The picture no wider than [`MAX_WIDTH`], by taking every so many pixels.
fn shrink(pixels: &[u8], width: u32, height: u32) -> (Vec<u8>, u32, u32) {
    if width <= MAX_WIDTH {
        return (pixels.to_vec(), width, height);
    }
    let step = width.div_ceil(MAX_WIDTH);
    let (small_w, small_h) = (width / step, height / step);
    let mut small = Vec::with_capacity((small_w * small_h * 4) as usize);
    for y in 0..small_h {
        let row = (y * step * width) as usize * 4;
        for x in 0..small_w {
            let at = row + (x * step) as usize * 4;
            small.extend_from_slice(&pixels[at..at + 4]);
        }
    }
    (small, small_w, small_h)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_wide_picture_is_made_smaller_and_keeps_its_shape() {
        let (w, h) = (1920u32, 1080u32);
        let pixels: Vec<u8> = (0..w * h).flat_map(|i| [(i % 256) as u8, 0, 0, 255]).collect();
        let (small, sw, sh) = shrink(&pixels, w, h);
        assert_eq!((sw, sh), (640, 360));
        assert_eq!(small.len(), (sw * sh * 4) as usize);
        // The first pixel of the second row is the first of the fourth.
        let at = (sw * 4) as usize;
        assert_eq!(small[at], ((3 * w) % 256) as u8);
    }

    #[test]
    fn a_small_picture_is_kept_as_it_is() {
        let pixels = vec![7u8; 640 * 480 * 4];
        let (same, w, h) = shrink(&pixels, 640, 480);
        assert_eq!((w, h), (640, 480));
        assert_eq!(same, pixels);
    }

    #[test]
    fn with_the_camera_off_there_is_no_picture() {
        stop();
        assert_eq!(state()["state"], "off");
        assert!(lock(&FRAME).is_none());
    }
}
