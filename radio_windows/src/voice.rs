//! The microphone and the speaker, for voice messages on Windows.
//!
//! Records an AAC sound file (.m4a), the same kind Android makes, and plays
//! one back. That is all it does. A recording is an ordinary file: sending
//! it, and sealing it for the person it is for, is the core's work.
//!
//! Not yet verified on devices.

use std::path::Path;
use std::sync::mpsc::{self, Sender};
use std::sync::Mutex;
use std::thread::{self, JoinHandle};

use windows::core::{Error, Result, HSTRING};
use windows::Media::Capture::{MediaCapture, MediaCaptureInitializationSettings, StreamingCaptureMode};
use windows::Media::Core::MediaSource;
use windows::Media::MediaProperties::{AudioEncodingQuality, MediaEncodingProfile};
use windows::Media::Playback::MediaPlayer;
use windows::Storage::{CreationCollisionOption, StorageFile, StorageFolder};

use crate::lock;

/// The recording under way, if there is one. Windows wants the recorder
/// used from the thread that made it, so that thread keeps it and waits
/// here to be told to stop.
struct Recording {
    stop: Sender<()>,
    /// Ends with whether the file was finished properly.
    finished: JoinHandle<bool>,
}

static RECORDING: Mutex<Option<Recording>> = Mutex::new(None);
/// What is playing, kept so it can be stopped. Letting go of it stops it.
static PLAYING: Mutex<Option<MediaPlayer>> = Mutex::new(None);

/// Does the work on a thread of its own and waits for it. The app calls in
/// on the thread that draws its window, and waiting on Windows there can
/// lock the window up.
fn on_worker<T: Send + 'static>(work: impl FnOnce() -> Result<T> + Send + 'static) -> Option<T> {
    thread::spawn(work).join().ok()?.ok()
}

/// Starts recording into the file at `path`. False if the microphone
/// cannot be used: there is none, or Windows has not been told this app
/// may use it.
pub fn start(path: String) -> bool {
    stop();
    let (started, has_started) = mpsc::channel();
    let (stop, told_to_stop) = mpsc::channel();
    let finished = thread::spawn(move || {
        let Ok(capture) = begin(&path) else {
            let _ = started.send(false);
            return false;
        };
        let _ = started.send(true);
        // Until told to stop, or until nobody is left to say so.
        let _ = told_to_stop.recv();
        capture.StopRecordAsync().and_then(|stopping| stopping.join()).and_then(|()| capture.Close()).is_ok()
    });
    if !has_started.recv().unwrap_or(false) {
        return false;
    }
    *lock(&RECORDING) = Some(Recording { stop, finished });
    true
}

fn begin(path: &str) -> Result<MediaCapture> {
    let path = Path::new(path);
    let (Some(folder), Some(name)) = (path.parent(), path.file_name()) else {
        return Err(Error::empty());
    };
    let folder = StorageFolder::GetFolderFromPathAsync(&HSTRING::from(folder))?.join()?;
    let file = folder.CreateFileAsync(&HSTRING::from(name), CreationCollisionOption::ReplaceExisting)?.join()?;

    let settings = MediaCaptureInitializationSettings::new()?;
    settings.SetStreamingCaptureMode(StreamingCaptureMode::Audio)?;
    let capture = MediaCapture::new()?;
    capture.InitializeWithSettingsAsync(&settings)?.join()?;
    // The smallest the Windows encoder makes. A voice message goes over
    // Bluetooth, so every byte counts.
    let profile = MediaEncodingProfile::CreateM4a(AudioEncodingQuality::Low)?;
    capture.StartRecordToStorageFileAsync(&profile, &file)?.join()?;
    Ok(capture)
}

/// Stops recording. The file is complete once this returns. False if
/// nothing was being recorded, or the file could not be finished.
pub fn stop() -> bool {
    let Some(recording) = lock(&RECORDING).take() else { return false };
    let _ = recording.stop.send(());
    recording.finished.join().unwrap_or(false)
}

/// Plays the sound file at `path` from its start. False if it cannot be
/// played.
pub fn play(path: String) -> bool {
    stop_playing();
    let player = on_worker(move || {
        let file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path))?.join()?;
        let player = MediaPlayer::new()?;
        player.SetSource(&MediaSource::CreateFromStorageFile(&file)?)?;
        player.Play()?;
        Ok(player)
    });
    let playing = player.is_some();
    *lock(&PLAYING) = player;
    playing
}

pub fn stop_playing() {
    if let Some(player) = lock(&PLAYING).take() {
        on_worker(move || {
            player.Pause()?;
            player.Close()
        });
    }
}
