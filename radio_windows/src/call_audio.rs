//! The microphone and the speaker during a call, on Windows.
//!
//! Sound moves as it is spoken, not as a file: the microphone hands over a
//! fiftieth of a second at a time, 16-bit samples, 16,000 a second, one
//! channel, and the speaker plays whatever the app gives it as soon as it
//! can. Squeezing the sound, sealing it and sending it are the core's work
//! and the app's; this only listens and plays.
//!
//! Both streams ask Windows for its communications processing, which on
//! most PCs takes out the echo of the speaker from the microphone and
//! quietens the room around it.
//!
//! Windows cannot call into the app, so what the microphone hears is kept
//! here until the app collects it, as the radio's events are.
//!
//! Not yet verified on devices.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};

use windows::core::Result;
use windows::Win32::Foundation::{CloseHandle, HANDLE, WAIT_OBJECT_0};
use windows::Win32::Media::Audio::{
    eCapture, eCommunications, eRender, AudioCategory_Communications, AudioClientProperties,
    EDataFlow, IAudioCaptureClient, IAudioClient, IAudioClient2, IAudioRenderClient,
    IMMDeviceEnumerator, MMDeviceEnumerator, AUDCLNT_BUFFERFLAGS_SILENT, AUDCLNT_SHAREMODE_SHARED,
    AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM, AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
    AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY, AUDCLNT_STREAMOPTIONS_NONE, WAVEFORMATEX,
    WAVE_FORMAT_PCM,
};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_ALL, COINIT_MULTITHREADED,
};
use windows::Win32::System::Threading::{CreateEventW, WaitForSingleObject};

use crate::lock;

const RATE: u32 = 16_000;
/// One block: a fiftieth of a second.
const BLOCK_SAMPLES: usize = (RATE / 50) as usize;
/// Blocks the microphone keeps for the app, at most. Older ones go: sound
/// that late is no use in a call.
const KEEP_BLOCKS: usize = 25;
/// Sound waiting to be played, at most: a quarter of a second. Beyond
/// that the oldest goes, so the call does not drift further and further
/// behind.
const KEEP_PLAYING: usize = RATE as usize / 4;
/// How long Windows holds for each stream, in hundreds of nanoseconds.
const BUFFER: i64 = 1_000_000;

struct Running {
    stop: Arc<AtomicBool>,
    threads: Vec<JoinHandle<()>>,
}

static RUNNING: Mutex<Option<Running>> = Mutex::new(None);
/// What the microphone heard, block by block.
static HEARD: Mutex<VecDeque<Vec<u8>>> = Mutex::new(VecDeque::new());
/// What is waiting to be played, sample by sample.
static TO_PLAY: Mutex<VecDeque<i16>> = Mutex::new(VecDeque::new());

fn format() -> WAVEFORMATEX {
    WAVEFORMATEX {
        wFormatTag: WAVE_FORMAT_PCM as u16,
        nChannels: 1,
        nSamplesPerSec: RATE,
        nAvgBytesPerSec: RATE * 2,
        nBlockAlign: 2,
        wBitsPerSample: 16,
        cbSize: 0,
    }
}

/// An event Windows sets each time a stream wants attention. Closed when
/// dropped.
struct Event(HANDLE);

impl Drop for Event {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseHandle(self.0);
        }
    }
}

/// Opens the default communications device for `flow` at 16 kHz, one
/// channel, and has Windows convert from whatever the device runs at.
unsafe fn open(flow: EDataFlow) -> Result<(IAudioClient, Event)> {
    let devices: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
    let device = devices.GetDefaultAudioEndpoint(flow, eCommunications)?;
    let client: IAudioClient = device.Activate(CLSCTX_ALL, None)?;
    // Asks for the processing made for calls: echo taken out, the room
    // quietened. Older Windows may not have it, and the call goes on
    // without.
    if let Ok(client2) = windows::core::Interface::cast::<IAudioClient2>(&client) {
        let properties = AudioClientProperties {
            cbSize: std::mem::size_of::<AudioClientProperties>() as u32,
            bIsOffload: false.into(),
            eCategory: AudioCategory_Communications,
            Options: AUDCLNT_STREAMOPTIONS_NONE,
        };
        let _ = client2.SetClientProperties(&properties);
    }
    let format = format();
    client.Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_EVENTCALLBACK
            | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM
            | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
        BUFFER,
        0,
        &format,
        None,
    )?;
    let event = Event(CreateEventW(None, false, false, None)?);
    client.SetEventHandle(event.0)?;
    Ok((client, event))
}

fn listen(stop: Arc<AtomicBool>, started: mpsc::Sender<bool>) {
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        let opened = open(eCapture).and_then(|(client, event)| {
            let capture: IAudioCaptureClient = client.GetService()?;
            client.Start()?;
            Ok((client, event, capture))
        });
        let Ok((client, event, capture)) = opened else {
            let _ = started.send(false);
            CoUninitialize();
            return;
        };
        let _ = started.send(true);
        let mut block: Vec<u8> = Vec::with_capacity(BLOCK_SAMPLES * 2);
        while !stop.load(Ordering::Relaxed) {
            if WaitForSingleObject(event.0, 200) != WAIT_OBJECT_0 {
                continue;
            }
            while let Ok(size) = capture.GetNextPacketSize() {
                if size == 0 {
                    break;
                }
                let mut data = std::ptr::null_mut();
                let (mut frames, mut flags) = (0u32, 0u32);
                if capture
                    .GetBuffer(&mut data, &mut frames, &mut flags, None, None)
                    .is_err()
                {
                    break;
                }
                let bytes = frames as usize * 2;
                let silent = flags & AUDCLNT_BUFFERFLAGS_SILENT.0 as u32 != 0;
                let samples: &[u8] = if silent || data.is_null() {
                    &[]
                } else {
                    std::slice::from_raw_parts(data, bytes)
                };
                for i in 0..bytes {
                    block.push(if silent { 0 } else { samples[i] });
                    if block.len() == BLOCK_SAMPLES * 2 {
                        let mut heard = lock(&HEARD);
                        heard.push_back(std::mem::replace(
                            &mut block,
                            Vec::with_capacity(BLOCK_SAMPLES * 2),
                        ));
                        while heard.len() > KEEP_BLOCKS {
                            heard.pop_front();
                        }
                    }
                }
                let _ = capture.ReleaseBuffer(frames);
            }
        }
        let _ = client.Stop();
        drop(event);
        CoUninitialize();
    }
}

fn speak(stop: Arc<AtomicBool>, started: mpsc::Sender<bool>) {
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        let opened = open(eRender).and_then(|(client, event)| {
            let render: IAudioRenderClient = client.GetService()?;
            let size = client.GetBufferSize()?;
            client.Start()?;
            Ok((client, event, render, size))
        });
        let Ok((client, event, render, size)) = opened else {
            let _ = started.send(false);
            CoUninitialize();
            return;
        };
        let _ = started.send(true);
        while !stop.load(Ordering::Relaxed) {
            if WaitForSingleObject(event.0, 200) != WAIT_OBJECT_0 {
                continue;
            }
            let Ok(padding) = client.GetCurrentPadding() else {
                continue;
            };
            let room = size.saturating_sub(padding);
            if room == 0 {
                continue;
            }
            let Ok(data) = render.GetBuffer(room) else {
                continue;
            };
            let out = std::slice::from_raw_parts_mut(data.cast::<i16>(), room as usize);
            {
                let mut waiting = lock(&TO_PLAY);
                for sample in out.iter_mut() {
                    // Nothing to play is silence, not a stop.
                    *sample = waiting.pop_front().unwrap_or(0);
                }
            }
            let _ = render.ReleaseBuffer(room, 0);
        }
        let _ = client.Stop();
        drop(event);
        CoUninitialize();
    }
}

/// Starts the microphone and the speaker. Says which of the two work. The
/// microphone fails where there is none, or where Windows has not been
/// told desktop apps may use it.
pub fn start() -> (bool, bool) {
    stop();
    // The sound threads join COM and leave it again; it must not close
    // under the other threads here when they do.
    crate::screen::keep_com();
    lock(&HEARD).clear();
    lock(&TO_PLAY).clear();
    let stop = Arc::new(AtomicBool::new(false));
    let (heard_tx, heard_rx) = mpsc::channel();
    let (play_tx, play_rx) = mpsc::channel();
    let listening = {
        let stop = stop.clone();
        thread::spawn(move || listen(stop, heard_tx))
    };
    let speaking = {
        let stop = stop.clone();
        thread::spawn(move || speak(stop, play_tx))
    };
    let mic = heard_rx.recv().unwrap_or(false);
    let speaker = play_rx.recv().unwrap_or(false);
    *lock(&RUNNING) = Some(Running {
        stop,
        threads: vec![listening, speaking],
    });
    (mic, speaker)
}

/// Hands over what the microphone heard since last asked, and queues
/// `play` for the speaker.
pub fn trade(play: Vec<Vec<u8>>) -> Vec<Vec<u8>> {
    if !play.is_empty() {
        let mut waiting = lock(&TO_PLAY);
        for block in play {
            waiting.extend(
                block
                    .chunks_exact(2)
                    .map(|pair| i16::from_le_bytes([pair[0], pair[1]])),
            );
        }
        let extra = waiting.len().saturating_sub(KEEP_PLAYING);
        waiting.drain(..extra);
    }
    lock(&HEARD).drain(..).collect()
}

/// Stops both. Nothing is kept.
pub fn stop() {
    let running = lock(&RUNNING).take();
    if let Some(running) = running {
        running.stop.store(true, Ordering::Relaxed);
        for thread in running.threads {
            let _ = thread.join();
        }
    }
    lock(&HEARD).clear();
    lock(&TO_PLAY).clear();
}
