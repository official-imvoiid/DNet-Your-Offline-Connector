//! Sharing the PC's screen, or one window on it, during a call.
//!
//! Nothing is looked at until the user has picked what to share, and
//! capture stops the moment the app says so, or when the window shared is
//! closed. Windows draws a coloured border round whatever is being
//! captured, so the user can always see it is going on. Pictures are kept
//! in memory only, and only as long as needed to send them.
//!
//! What is captured goes out in pieces: the picture is cut into squares,
//! and only squares that changed since they were last sent are squeezed
//! into JPEG and handed over. A screen is mostly still, so text stays
//! sharp at full size, and when much changes at once it simply arrives a
//! little later: the app sets how many bytes a second may go, and the
//! squares wait their turn. Sealing and sending them are the core's work
//! and the app's.
//!
//! Not yet verified on devices.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use windows::core::{factory, w, Interface, Result, BOOL, PWSTR};
use windows::Foundation::TypedEventHandler;
use windows::Graphics::Capture::{Direct3D11CaptureFramePool, GraphicsCaptureItem, GraphicsCaptureSession};
use windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
use windows::Graphics::DirectX::DirectXPixelFormat;
use windows::Win32::Foundation::{HGLOBAL, HMODULE, HWND, LPARAM, RECT};
use windows::Win32::Graphics::Direct3D::{D3D_DRIVER_TYPE, D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_WARP};
use windows::Win32::Graphics::Direct3D11::{
    D3D11CreateDevice, ID3D11Device, ID3D11DeviceContext, ID3D11Texture2D, D3D11_CPU_ACCESS_READ,
    D3D11_CREATE_DEVICE_BGRA_SUPPORT, D3D11_MAPPED_SUBRESOURCE, D3D11_MAP_READ, D3D11_SDK_VERSION,
    D3D11_TEXTURE2D_DESC, D3D11_USAGE_STAGING,
};
use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED};
use windows::Win32::Graphics::Dxgi::IDXGIDevice;
use windows::Win32::Graphics::Gdi::{EnumDisplayMonitors, GetMonitorInfoW, HDC, HMONITOR, MONITORINFO};
use windows::Win32::Graphics::Imaging::{
    CLSID_WICImagingFactory, GUID_ContainerFormatJpeg, GUID_WICPixelFormat24bppBGR, IWICImagingFactory,
    WICBitmapEncoderNoCache,
};
use windows::Win32::System::Com::StructuredStorage::{CreateStreamOnHGlobal, IPropertyBag2, PROPBAG2};
use windows::Win32::System::Com::{
    CoCreateInstance, CoIncrementMTAUsage, CLSCTX_INPROC_SERVER, STREAM_SEEK_CUR, STREAM_SEEK_SET,
};
use windows::Win32::System::Threading::GetCurrentProcessId;
use windows::Win32::System::Variant::{VARIANT, VARIANT_0, VARIANT_0_0, VARIANT_0_0_0, VT_R4};
use windows::Win32::System::WinRT::Direct3D11::{CreateDirect3D11DeviceFromDXGIDevice, IDirect3DDxgiInterfaceAccess};
use windows::Win32::System::WinRT::Graphics::Capture::IGraphicsCaptureItemInterop;
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetShellWindow, GetWindow, GetWindowLongW, GetWindowTextW, GetWindowThreadProcessId, IsIconic,
    IsWindow, IsWindowVisible, GWL_EXSTYLE, GW_OWNER, WS_EX_TOOLWINDOW,
};

use crate::{lock, to_hex};

/// The side of each square the picture is cut into. Small enough that
/// even a square full of text fits one frame as JPEG.
pub const TILE: u32 = 192;
/// The most one square may take once squeezed: a frame on the local
/// network holds 16 KB, and the core and the app each put a little in
/// front of it.
pub const MOST_BYTES: usize = 15 * 1024 - 32;
/// How often the screen is looked at: up to five times a second.
const EVERY: Duration = Duration::from_millis(200);
/// JPEG qualities to try, best first, until a square fits.
const QUALITIES: [f32; 3] = [0.72, 0.55, 0.4];
/// How long a burst may run ahead of the rate, so a single click that
/// changes a few squares goes at once.
const BURST: f64 = 0.5;

/// One square, ready to send. `x`, `y`, `w` and `h` are where it goes on a
/// picture `width` by `height`, and `gen` changes whenever that picture's
/// size does, so old squares are never put on a new picture.
#[derive(Clone, Debug, PartialEq)]
pub struct Piece {
    pub gen: u16,
    pub width: u32,
    pub height: u32,
    pub x: u32,
    pub y: u32,
    pub w: u32,
    pub h: u32,
    pub jpeg: Vec<u8>,
}

struct Share {
    /// Which sharing this is. One that was stopped must not speak for the
    /// next.
    turn: u32,
    /// "off", "starting", "on", or why it is not on: "ended" (the window
    /// shared was closed) or "failed".
    state: &'static str,
    stop: Option<Sender<()>>,
    /// Bytes a second the app lets go, and how wide a picture is sent.
    rate: u32,
    width: u32,
    /// Someone new is watching: send everything again.
    refresh: bool,
    ready: VecDeque<Piece>,
}

static SHARE: Mutex<Share> = Mutex::new(Share {
    turn: 0,
    state: "off",
    stop: None,
    rate: 300_000,
    width: 1920,
    refresh: false,
    ready: VecDeque::new(),
});

/// What can be shared: each screen, then each window the user has open,
/// DNet's own left out. Empty where Windows cannot capture at all.
pub fn sources() -> Value {
    if !GraphicsCaptureSession::IsSupported().unwrap_or(false) {
        return json!([]);
    }
    let mut all: Vec<Value> = monitors()
        .into_iter()
        .map(|(monitor, primary, width, height)| {
            json!({
                "id": format!("screen:{}", monitor.0 as isize),
                "kind": "screen",
                "primary": primary,
                "width": width,
                "height": height,
            })
        })
        .collect();
    all.extend(windows_open().into_iter().map(
        |(window, name)| json!({ "id": format!("window:{}", window.0 as isize), "kind": "window", "name": name }),
    ));
    Value::Array(all)
}

fn monitors() -> Vec<(HMONITOR, bool, i32, i32)> {
    unsafe extern "system" fn each(monitor: HMONITOR, _: HDC, _: *mut RECT, found: LPARAM) -> BOOL {
        let found = &mut *(found.0 as *mut Vec<(HMONITOR, bool, i32, i32)>);
        let mut info = MONITORINFO { cbSize: size_of::<MONITORINFO>() as u32, ..Default::default() };
        if GetMonitorInfoW(monitor, &mut info).as_bool() {
            let area = info.rcMonitor;
            // MONITORINFOF_PRIMARY.
            let primary = info.dwFlags & 1 != 0;
            found.push((monitor, primary, area.right - area.left, area.bottom - area.top));
        }
        BOOL(1)
    }
    let mut found: Vec<(HMONITOR, bool, i32, i32)> = vec![];
    unsafe {
        let _ = EnumDisplayMonitors(None, None, Some(each), LPARAM(&mut found as *mut _ as isize));
    }
    // The main screen first.
    found.sort_by_key(|(_, primary, _, _)| !*primary);
    found
}

fn windows_open() -> Vec<(HWND, String)> {
    unsafe extern "system" fn each(window: HWND, found: LPARAM) -> BOOL {
        let found = &mut *(found.0 as *mut Vec<(HWND, String)>);
        if let Some(name) = shareable(window) {
            found.push((window, name));
        }
        BOOL(1)
    }
    let mut found: Vec<(HWND, String)> = vec![];
    unsafe {
        let _ = EnumWindows(Some(each), LPARAM(&mut found as *mut _ as isize));
    }
    found
}

/// The window's title, if it is one a person would think of sharing: on
/// screen, not minimised, not a tool palette or a pop-up of another, not
/// hidden by Windows, and not DNet's own.
fn shareable(window: HWND) -> Option<String> {
    unsafe {
        if !IsWindowVisible(window).as_bool() || IsIconic(window).as_bool() || window == GetShellWindow() {
            return None;
        }
        if GetWindow(window, GW_OWNER).is_ok_and(|owner| !owner.is_invalid()) {
            return None;
        }
        if GetWindowLongW(window, GWL_EXSTYLE) as u32 & WS_EX_TOOLWINDOW.0 != 0 {
            return None;
        }
        let mut cloaked = 0u32;
        let _ = DwmGetWindowAttribute(window, DWMWA_CLOAKED, &mut cloaked as *mut u32 as _, size_of::<u32>() as u32);
        if cloaked != 0 {
            return None;
        }
        let mut process = 0u32;
        GetWindowThreadProcessId(window, Some(&mut process));
        if process == GetCurrentProcessId() {
            return None;
        }
        let mut title = [0u16; 256];
        let len = GetWindowTextW(window, &mut title);
        let name = String::from_utf16_lossy(&title[..len.max(0) as usize]).trim().to_string();
        (!name.is_empty()).then_some(name)
    }
}

/// Starts sharing what `source` names, as [`sources`] gave it. False if it
/// names nothing that can be shared now. Whether capture really began
/// shows in [`state`] a moment later.
pub fn start(source: &str) -> bool {
    let Some(target) = target_of(source) else {
        return false;
    };
    stop();
    let (tell, told) = channel();
    let turn = {
        let mut share = lock(&SHARE);
        share.turn += 1;
        share.state = "starting";
        share.stop = Some(tell);
        share.refresh = false;
        share.ready.clear();
        share.turn
    };
    thread::spawn(move || {
        keep_com();
        if hold(turn, target, told).is_err() {
            set(turn, "failed");
        }
    });
    true
}

/// Keeps COM's shared apartment open for as long as the app runs, so the
/// thread that shares the screen can use Windows' JPEG encoder. Joining
/// and leaving it from this thread instead could close it under the other
/// threads here that use it without joining (Bluetooth, the camera, voice
/// messages), and crash them.
pub(crate) fn keep_com() {
    static KEPT: std::sync::Once = std::sync::Once::new();
    KEPT.call_once(|| {
        // Never given back: the apartment stays until the app closes.
        let _ = unsafe { CoIncrementMTAUsage() };
    });
}

#[derive(Clone, Copy)]
enum Target {
    Monitor(isize),
    Window(isize),
}

fn target_of(source: &str) -> Option<Target> {
    let (kind, number) = source.split_once(':')?;
    let number: isize = number.parse().ok()?;
    match kind {
        "screen" if monitors().iter().any(|(m, ..)| m.0 as isize == number) => Some(Target::Monitor(number)),
        "window" if unsafe { IsWindow(Some(HWND(number as _))).as_bool() } => Some(Target::Window(number)),
        _ => None,
    }
}

/// Stops sharing, if it is on. Whatever was waiting to be sent goes too.
pub fn stop() {
    let mut share = lock(&SHARE);
    share.turn += 1;
    share.state = "off";
    share.ready.clear();
    if let Some(stop) = share.stop.take() {
        let _ = stop.send(());
    }
}

/// How many bytes a second may go, and how wide a picture is sent. Set by
/// the app from the link and how many are watching.
pub fn rate(bytes: u32, width: u32) {
    let mut share = lock(&SHARE);
    share.rate = bytes.clamp(8_000, 20_000_000);
    share.width = width.clamp(320, 3840);
}

/// Sends the whole picture again, for someone who has just started
/// watching.
pub fn refresh() {
    lock(&SHARE).refresh = true;
}

pub fn state() -> Value {
    json!({ "state": lock(&SHARE).state })
}

/// The squares ready to send, and the state, for the app to collect.
pub fn take() -> Value {
    let mut share = lock(&SHARE);
    let pieces: Vec<Value> = share
        .ready
        .drain(..)
        .map(|p| {
            json!({
                "gen": p.gen, "width": p.width, "height": p.height,
                "x": p.x, "y": p.y, "w": p.w, "h": p.h,
                "jpeg": to_hex(&p.jpeg),
            })
        })
        .collect();
    json!({ "state": share.state, "pieces": pieces })
}

fn set(turn: u32, state: &'static str) {
    let mut share = lock(&SHARE);
    if share.turn == turn {
        share.state = state;
        if state != "on" && state != "starting" {
            share.stop = None;
        }
    }
}

fn device() -> Result<(ID3D11Device, ID3D11DeviceContext, IDirect3DDevice)> {
    fn make(kind: D3D_DRIVER_TYPE) -> Result<(ID3D11Device, ID3D11DeviceContext)> {
        let (mut device, mut context) = (None, None);
        unsafe {
            D3D11CreateDevice(
                None,
                kind,
                HMODULE::default(),
                D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                None,
                D3D11_SDK_VERSION,
                Some(&mut device),
                None,
                Some(&mut context),
            )?;
        }
        Ok((device.expect("made when Ok"), context.expect("made when Ok")))
    }
    // With no graphics card to use, Windows draws in software.
    let (device, context) = make(D3D_DRIVER_TYPE_HARDWARE).or_else(|_| make(D3D_DRIVER_TYPE_WARP))?;
    let dxgi: IDXGIDevice = device.cast()?;
    let shared: IDirect3DDevice = unsafe { CreateDirect3D11DeviceFromDXGIDevice(&dxgi)? }.cast()?;
    Ok((device, context, shared))
}

/// Captures until told to stop, cutting each picture into squares and
/// squeezing the changed ones as the rate allows.
fn hold(turn: u32, target: Target, told: Receiver<()>) -> Result<()> {
    let interop = factory::<GraphicsCaptureItem, IGraphicsCaptureItemInterop>()?;
    let item: GraphicsCaptureItem = unsafe {
        match target {
            Target::Monitor(m) => interop.CreateForMonitor(HMONITOR(m as _))?,
            Target::Window(w) => interop.CreateForWindow(HWND(w as _))?,
        }
    };
    let closed = Arc::new(AtomicBool::new(false));
    let heard = closed.clone();
    item.Closed(&TypedEventHandler::new(move |_, _| {
        heard.store(true, Ordering::SeqCst);
        Ok(())
    }))?;
    let (device, context, shared) = device()?;
    let format = DirectXPixelFormat::B8G8R8A8UIntNormalized;
    let mut size = item.Size()?;
    let pool = Direct3D11CaptureFramePool::CreateFreeThreaded(&shared, format, 2, size)?;
    let session = pool.CreateCaptureSession(&item)?;
    let _ = session.SetIsCursorCaptureEnabled(true);
    session.StartCapture()?;
    set(turn, "on");

    let wic: IWICImagingFactory = unsafe { CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER)? };
    // Each sharing numbers its pictures apart from the last one's, so a
    // square of an earlier sharing is never put on this one.
    let mut tiler = Tiler::numbered_from((turn as u16).wrapping_mul(1009));
    let mut staging: Option<(ID3D11Texture2D, u32, u32)> = None;
    let mut last = Instant::now();
    loop {
        match told.recv_timeout(EVERY) {
            Ok(()) | Err(RecvTimeoutError::Disconnected) => break,
            Err(RecvTimeoutError::Timeout) => {}
        }
        if closed.load(Ordering::SeqCst) {
            set(turn, "ended");
            break;
        }
        // Only the newest picture matters.
        let mut newest = None;
        while let Ok(frame) = pool.TryGetNextFrame() {
            newest = Some(frame);
        }
        let (rate, width, refresh) = {
            let mut share = lock(&SHARE);
            if share.turn != turn {
                break;
            }
            (share.rate, share.width, std::mem::take(&mut share.refresh))
        };
        if refresh {
            tiler.refresh();
        }
        if let Some(frame) = newest {
            let content = frame.ContentSize()?;
            let texture: ID3D11Texture2D =
                unsafe { frame.Surface()?.cast::<IDirect3DDxgiInterfaceAccess>()?.GetInterface()? };
            let grabbed = read(&device, &context, &texture, &mut staging, content.Width, content.Height)?;
            drop(frame);
            if content.Width != size.Width || content.Height != size.Height {
                // A window was resized: later pictures come at the new size.
                size = content;
                pool.Recreate(&shared, format, 2, size)?;
            }
            if let Some((pixels, w, h)) = grabbed {
                let (pixels, w, h) = scale(pixels, w, h, width);
                tiler.look(pixels, w, h);
            }
        }
        let spent = last.elapsed().as_secs_f64();
        last = Instant::now();
        let pieces = tiler.spend(rate as f64, spent, &mut |bgr, w, h, quality| jpeg(&wic, bgr, w, h, quality).ok());
        if !pieces.is_empty() {
            let mut share = lock(&SHARE);
            if share.turn != turn {
                break;
            }
            share.ready.extend(pieces);
        }
    }
    let _ = session.Close();
    let _ = pool.Close();
    Ok(())
}

/// Copies the captured picture out of the graphics card: BGRA, row after
/// row, `width` by `height` at most.
fn read(
    device: &ID3D11Device,
    context: &ID3D11DeviceContext,
    texture: &ID3D11Texture2D,
    staging: &mut Option<(ID3D11Texture2D, u32, u32)>,
    width: i32,
    height: i32,
) -> Result<Option<(Vec<u8>, u32, u32)>> {
    let mut desc = D3D11_TEXTURE2D_DESC::default();
    unsafe { texture.GetDesc(&mut desc) };
    if !staging.as_ref().is_some_and(|(_, w, h)| *w == desc.Width && *h == desc.Height) {
        let mut copy = desc;
        copy.Usage = D3D11_USAGE_STAGING;
        copy.BindFlags = 0;
        copy.CPUAccessFlags = D3D11_CPU_ACCESS_READ.0 as u32;
        copy.MiscFlags = 0;
        copy.MipLevels = 1;
        copy.ArraySize = 1;
        let mut made = None;
        unsafe { device.CreateTexture2D(&copy, None, Some(&mut made))? };
        *staging = made.map(|t| (t, desc.Width, desc.Height));
    }
    let Some((copy, ..)) = staging.as_ref() else {
        return Ok(None);
    };
    let (w, h) = ((width.max(0) as u32).min(desc.Width), (height.max(0) as u32).min(desc.Height));
    if w == 0 || h == 0 {
        return Ok(None);
    }
    unsafe {
        context.CopyResource(copy, texture);
        let mut mapped = D3D11_MAPPED_SUBRESOURCE::default();
        context.Map(copy, 0, D3D11_MAP_READ, 0, Some(&mut mapped))?;
        let mut pixels = Vec::with_capacity((w * h * 4) as usize);
        for row in 0..h {
            let start = (mapped.pData as *const u8).add((row * mapped.RowPitch) as usize);
            pixels.extend_from_slice(std::slice::from_raw_parts(start, (w * 4) as usize));
        }
        context.Unmap(copy, 0);
        Ok(Some((pixels, w, h)))
    }
}

/// Squeezes BGR pixels into JPEG at `quality` (0 to 1). Fails if it does
/// not fit [`MOST_BYTES`].
fn jpeg(wic: &IWICImagingFactory, bgr: &[u8], width: u32, height: u32, quality: f32) -> Result<Vec<u8>> {
    unsafe {
        // A stream that grows as it is written, so the encoder never runs
        // out of room part way: whether the JPEG fits is checked after.
        let stream = CreateStreamOnHGlobal(HGLOBAL::default(), true)?;
        let encoder = wic.CreateEncoder(&GUID_ContainerFormatJpeg, std::ptr::null())?;
        encoder.Initialize(&stream, WICBitmapEncoderNoCache)?;
        let (mut frame, mut options): (_, Option<IPropertyBag2>) = (None, None);
        encoder.CreateNewFrame(&mut frame, &mut options)?;
        let frame = frame.ok_or_else(windows::core::Error::empty)?;
        if let Some(options) = &options {
            let name = PROPBAG2 { pstrName: PWSTR(w!("ImageQuality").as_ptr() as *mut u16), ..Default::default() };
            let value = VARIANT {
                Anonymous: VARIANT_0 {
                    Anonymous: std::mem::ManuallyDrop::new(VARIANT_0_0 {
                        vt: VT_R4,
                        Anonymous: VARIANT_0_0_0 { fltVal: quality },
                        ..Default::default()
                    }),
                },
            };
            options.Write(1, &name, &value)?;
        }
        frame.Initialize(options.as_ref())?;
        frame.SetSize(width, height)?;
        let mut format = GUID_WICPixelFormat24bppBGR;
        frame.SetPixelFormat(&mut format)?;
        if format != GUID_WICPixelFormat24bppBGR {
            return Err(windows::core::Error::empty());
        }
        frame.WritePixels(height, width * 3, bgr)?;
        frame.Commit()?;
        encoder.Commit()?;
        let mut used = 0u64;
        stream.Seek(0, STREAM_SEEK_CUR, Some(&mut used))?;
        if used as usize > MOST_BYTES {
            return Err(windows::core::Error::empty());
        }
        let mut out = vec![0u8; used as usize];
        let mut read = 0u32;
        stream.Seek(0, STREAM_SEEK_SET, None)?;
        stream.Read(out.as_mut_ptr().cast(), used as u32, Some(&mut read)).ok()?;
        out.truncate(read as usize);
        let whole = out.len() > 4 && out.starts_with(&[0xff, 0xd8]) && out.ends_with(&[0xff, 0xd9]);
        if !whole {
            return Err(windows::core::Error::empty());
        }
        Ok(out)
    }
}

/// The picture no wider than `most`, each pixel the average of those it
/// covers, so small text stays as legible as it can. Alpha is dropped.
pub fn scale(pixels: Vec<u8>, width: u32, height: u32, most: u32) -> (Vec<u8>, u32, u32) {
    if width <= most || most == 0 {
        return (pixels, width, height);
    }
    let (new_w, new_h) = (most, ((height as u64 * most as u64) / width as u64).max(1) as u32);
    let span = |i: u32, from: u32, to: u32| {
        let start = (i as u64 * from as u64 / to as u64) as u32;
        let end = (((i + 1) as u64 * from as u64).div_ceil(to as u64) as u32).clamp(start + 1, from);
        (start, end)
    };
    let columns: Vec<(u32, u32)> = (0..new_w).map(|x| span(x, width, new_w)).collect();
    let mut out = Vec::with_capacity((new_w * new_h * 4) as usize);
    for y in 0..new_h {
        let (top, bottom) = span(y, height, new_h);
        for &(left, right) in &columns {
            let mut sum = [0u32; 3];
            for row in top..bottom {
                let at = ((row * width + left) * 4) as usize;
                for pixel in pixels[at..at + ((right - left) * 4) as usize].chunks_exact(4) {
                    sum[0] += pixel[0] as u32;
                    sum[1] += pixel[1] as u32;
                    sum[2] += pixel[2] as u32;
                }
            }
            let count = (bottom - top) * (right - left);
            out.extend_from_slice(&[(sum[0] / count) as u8, (sum[1] / count) as u8, (sum[2] / count) as u8, 255]);
        }
    }
    (out, new_w, new_h)
}

/// Makes JPEG of BGR pixels, `width` by `height`, at a quality from 0 to
/// 1, or nothing if it would not fit one frame.
pub type Encode<'a> = &'a mut dyn FnMut(&[u8], u32, u32, f32) -> Option<Vec<u8>>;

/// Cuts pictures into squares and keeps track of which have changed since
/// they were last sent.
#[derive(Default)]
pub struct Tiler {
    gen: u16,
    width: u32,
    height: u32,
    pixels: Vec<u8>,
    /// What each square held when last sent: 0 for never.
    sent: Vec<u64>,
    /// What each square holds now.
    now: Vec<u64>,
    /// Bytes that may still go.
    allowance: f64,
}

impl Tiler {
    /// A tiler whose first picture is numbered just after `gen`.
    pub fn numbered_from(gen: u16) -> Self {
        Self { gen, ..Self::default() }
    }

    fn columns(&self) -> u32 {
        self.width.div_ceil(TILE)
    }

    /// Takes in the newest picture, BGRA.
    pub fn look(&mut self, pixels: Vec<u8>, width: u32, height: u32) {
        if width != self.width || height != self.height {
            self.gen = self.gen.wrapping_add(1);
            self.width = width;
            self.height = height;
            let count = (width.div_ceil(TILE) * height.div_ceil(TILE)) as usize;
            self.sent = vec![0; count];
        }
        self.pixels = pixels;
        self.now = (0..self.sent.len()).map(|i| self.hash(self.rect(i))).collect();
    }

    /// Everything counts as changed: it is all sent again.
    pub fn refresh(&mut self) {
        self.sent.fill(0);
    }

    fn rect(&self, index: usize) -> (u32, u32, u32, u32) {
        let (column, row) = (index as u32 % self.columns(), index as u32 / self.columns());
        let (x, y) = (column * TILE, row * TILE);
        (x, y, TILE.min(self.width - x), TILE.min(self.height - y))
    }

    fn hash(&self, (x, y, w, h): (u32, u32, u32, u32)) -> u64 {
        let mut hash = 0xcbf2_9ce4_8422_2325u64;
        for row in y..y + h {
            let at = ((row * self.width + x) * 4) as usize;
            for pixel in self.pixels[at..at + (w * 4) as usize].chunks_exact(4) {
                let value = u32::from_le_bytes([pixel[0], pixel[1], pixel[2], 0]) as u64;
                hash = (hash ^ value).wrapping_mul(0x0100_0000_01b3);
            }
        }
        // Never 0, which means "never sent".
        hash | 1
    }

    /// BGR pixels of part of the picture, for the JPEG encoder.
    fn bgr(&self, (x, y, w, h): (u32, u32, u32, u32)) -> Vec<u8> {
        let mut out = Vec::with_capacity((w * h * 3) as usize);
        for row in y..y + h {
            let at = ((row * self.width + x) * 4) as usize;
            for pixel in self.pixels[at..at + (w * 4) as usize].chunks_exact(4) {
                out.extend_from_slice(&pixel[..3]);
            }
        }
        out
    }

    /// Squeezes changed squares, in order, while the allowance lasts:
    /// `rate` bytes a second, `seconds` since last time. `encode` makes
    /// JPEG of BGR pixels at a quality, or nothing if it would not fit.
    /// A square that will not fit even at the lowest quality goes as four
    /// quarters.
    pub fn spend(&mut self, rate: f64, seconds: f64, encode: Encode) -> Vec<Piece> {
        self.allowance = (self.allowance + rate * seconds).min(rate * BURST);
        let mut pieces = vec![];
        for index in 0..self.sent.len() {
            if self.allowance <= 0.0 {
                break;
            }
            if self.sent[index] == self.now[index] {
                continue;
            }
            let rect = self.rect(index);
            let made = self.squeeze(rect, encode);
            if made.is_empty() {
                continue;
            }
            self.allowance -= made.iter().map(|p| p.jpeg.len()).sum::<usize>() as f64;
            self.sent[index] = self.now[index];
            pieces.extend(made);
        }
        pieces
    }

    fn squeeze(&self, rect: (u32, u32, u32, u32), encode: Encode) -> Vec<Piece> {
        let (x, y, w, h) = rect;
        let bgr = self.bgr(rect);
        for quality in QUALITIES {
            if let Some(jpeg) = encode(&bgr, w, h, quality).filter(|j| j.len() <= MOST_BYTES) {
                return vec![Piece { gen: self.gen, width: self.width, height: self.height, x, y, w, h, jpeg }];
            }
        }
        if w < 16 || h < 16 {
            return vec![];
        }
        let (half_w, half_h) = (w / 2, h / 2);
        [
            (x, y, half_w, half_h),
            (x + half_w, y, w - half_w, half_h),
            (x, y + half_h, half_w, h - half_h),
            (x + half_w, y + half_h, w - half_w, h - half_h),
        ]
        .into_iter()
        .flat_map(|quarter| self.squeeze(quarter, encode))
        .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A picture of stripes, BGRA.
    fn picture(width: u32, height: u32, shade: u8) -> Vec<u8> {
        (0..width * height).flat_map(|i| [shade, (i % 251) as u8, (i % 7) as u8 * 30, 255]).collect()
    }

    fn fake(bgr: &[u8], w: u32, h: u32, _: f32) -> Option<Vec<u8>> {
        assert_eq!(bgr.len(), (w * h * 3) as usize);
        Some(vec![0xff, 0xd8, w as u8, h as u8])
    }

    #[test]
    fn a_wide_picture_is_made_smaller_by_averaging() {
        // Two pixels, one black and one white, become one grey one.
        let pixels = [0, 0, 0, 255, 255, 255, 255, 255];
        let (small, w, h) = scale(pixels.to_vec(), 2, 1, 1);
        assert_eq!((w, h), (1, 1));
        assert_eq!(small, vec![127, 127, 127, 255]);
        let (same, w, h) = scale(picture(640, 480, 9), 640, 480, 1920);
        assert_eq!((w, h), (640, 480));
        assert_eq!(same.len(), 640 * 480 * 4);
        let (_, w, h) = scale(picture(2560, 1440, 9), 2560, 1440, 1920);
        assert_eq!((w, h), (1920, 1080));
    }

    #[test]
    fn the_first_picture_goes_whole_and_then_only_what_changed() {
        let mut tiler = Tiler::default();
        let (w, h) = (400, 200);
        tiler.look(picture(w, h, 1), w, h);
        let first = tiler.spend(10_000_000.0, 1.0, &mut fake);
        // 400 x 200 in squares of 192: three across, two down.
        assert_eq!(first.len(), 6);
        assert_eq!((first[2].x, first[2].w), (384, 16));
        assert_eq!((first[5].y, first[5].h), (192, 8));
        assert!(first.iter().all(|p| p.width == w && p.height == h));

        tiler.look(picture(w, h, 1), w, h);
        assert!(tiler.spend(10_000_000.0, 1.0, &mut fake).is_empty(), "nothing changed");

        // One pixel changes, in the middle square of the top row.
        let mut changed = picture(w, h, 1);
        changed[((10 * w + 200) * 4) as usize] ^= 0xff;
        tiler.look(changed, w, h);
        let again = tiler.spend(10_000_000.0, 1.0, &mut fake);
        assert_eq!(again.len(), 1);
        assert_eq!((again[0].x, again[0].y), (192, 0));
    }

    #[test]
    fn with_little_allowed_squares_wait_their_turn_instead_of_shrinking() {
        let mut tiler = Tiler::default();
        let (w, h) = (192 * 4, 192);
        tiler.look(picture(w, h, 2), w, h);
        let mut big = |_: &[u8], _: u32, _: u32, _: f32| Some(vec![1u8; 10_000]);
        // 10 KB a second, a fifth of a second at a time: one square a
        // second, each at full size.
        let mut sent = 0;
        let mut ticks = 0;
        while sent < 4 {
            sent += tiler.spend(10_000.0, 0.2, &mut big).len();
            ticks += 1;
            assert!(ticks < 40, "everything is sent in the end");
        }
        assert!(ticks >= 8, "it took {ticks} ticks");
    }

    #[test]
    fn a_square_that_will_not_fit_goes_in_quarters() {
        let mut tiler = Tiler::default();
        tiler.look(picture(192, 192, 3), 192, 192);
        let mut picky = |_: &[u8], w: u32, h: u32, _: f32| (w < 192).then(|| vec![w as u8, h as u8]);
        let pieces = tiler.spend(1_000_000.0, 1.0, &mut picky);
        assert_eq!(pieces.len(), 4);
        assert_eq!(pieces.iter().map(|p| p.w * p.h).sum::<u32>(), 192 * 192);
    }

    #[test]
    fn a_new_size_starts_a_new_picture_and_a_refresh_sends_it_all_again() {
        let mut tiler = Tiler::default();
        tiler.look(picture(200, 100, 4), 200, 100);
        let first = tiler.spend(1e7, 1.0, &mut fake);
        tiler.look(picture(300, 100, 4), 300, 100);
        let second = tiler.spend(1e7, 1.0, &mut fake);
        assert_ne!(first[0].gen, second[0].gen);
        tiler.refresh();
        assert_eq!(tiler.spend(1e7, 1.0, &mut fake).len(), second.len());
    }

    #[test]
    fn real_jpeg_of_a_square_fits_one_frame() {
        keep_com();
        {
            let wic: IWICImagingFactory =
                unsafe { CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER).unwrap() };
            let bgr: Vec<u8> = (0..TILE * TILE).flat_map(|i| [(i % 256) as u8, (i / 7 % 256) as u8, 200]).collect();
            let made = jpeg(&wic, &bgr, TILE, TILE, QUALITIES[0]).unwrap();
            assert_eq!(&made[..2], &[0xff, 0xd8]);
            assert!(made.len() <= MOST_BYTES);
            // Noise does not fit; the caller tries lower, then quarters.
            let noise: Vec<u8> = (0..TILE * TILE * 3).map(|i| (i.wrapping_mul(2_654_435_761) >> 13) as u8).collect();
            assert!(jpeg(&wic, &noise, TILE, TILE, 1.0).is_err());
        }
    }

    #[test]
    fn nothing_is_shared_until_something_is_picked() {
        stop();
        assert_eq!(state()["state"], "off");
        assert_eq!(take()["pieces"], json!([]));
        assert!(!start("window:0"));
        assert!(!start("screen:nonsense"));
        assert!(!start("somewhere"));
        assert_eq!(state()["state"], "off");
    }
}
