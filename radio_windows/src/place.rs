//! Where this PC is, for a user who chose to send it, and a map to show a
//! place someone sent.
//!
//! Windows works the place out (from GPS if the PC has one, otherwise from
//! the Wi-Fi networks around it) and answers in its own time, so asking
//! starts the search and `state` says how it went. Nothing is looked up
//! until the user asks, and the place is not kept here once the app has
//! it.
//!
//! Not yet verified on devices.

use std::sync::Mutex;
use std::thread;
use std::time::Duration;

use serde_json::{json, Value};
use windows::core::HSTRING;
use windows::Devices::Geolocation::{
    GeolocationAccessStatus, Geolocator, PositionAccuracy, PositionStatus,
};
use windows::Foundation::{TimeSpan, Uri};
use windows::System::Launcher;

use crate::lock;

struct Search {
    /// Which search this is. One that was given up must not speak for the
    /// next.
    turn: u32,
    /// "off", "busy", "ok", or why there is no place: "denied" (Windows
    /// does not let desktop apps have it), "off_here" (location is off on
    /// this PC), "none" (nothing on it can tell) or "failed".
    state: &'static str,
    /// Degrees north and east, and how far off, in metres.
    found: Option<(f64, f64, f64)>,
}

static SEARCH: Mutex<Search> = Mutex::new(Search { turn: 0, state: "off", found: None });

/// The most a place found earlier may be out of date and still count as
/// where the PC is now.
const MAX_AGE: Duration = Duration::from_secs(60);
/// How long to wait for Windows before saying it could not tell.
const TIMEOUT: Duration = Duration::from_secs(30);

/// Starts working out where this PC is. The first time, Windows may ask the
/// user whether the app may know.
pub fn start() {
    let turn = {
        let mut search = lock(&SEARCH);
        search.turn += 1;
        search.state = "busy";
        search.found = None;
        search.turn
    };
    thread::spawn(move || {
        let (state, found) = match find() {
            Ok(place) => ("ok", Some(place)),
            Err(why) => (why, None),
        };
        let mut search = lock(&SEARCH);
        if search.turn == turn {
            search.state = state;
            search.found = found;
        }
    });
}

pub fn state() -> Value {
    let search = lock(&SEARCH);
    match search.found {
        Some((lat, lon, accuracy)) => {
            json!({ "state": search.state, "lat": lat, "lon": lon, "accuracy": accuracy })
        }
        None => json!({ "state": search.state }),
    }
}

/// Forgets the search and what it found.
pub fn stop() {
    let mut search = lock(&SEARCH);
    search.turn += 1;
    search.state = "off";
    search.found = None;
}

fn find() -> Result<(f64, f64, f64), &'static str> {
    // Windows asks the user the first time and remembers the answer.
    if let Ok(GeolocationAccessStatus::Denied) =
        Geolocator::RequestAccessAsync().and_then(|asking| asking.join())
    {
        return Err("denied");
    }
    let locator = Geolocator::new().map_err(|_| "failed")?;
    let _ = locator.SetDesiredAccuracy(PositionAccuracy::High);
    match locator.LocationStatus() {
        Ok(PositionStatus::Disabled) => return Err("off_here"),
        Ok(PositionStatus::NotAvailable) => return Err("none"),
        _ => {}
    }
    let fix = locator
        .GetGeopositionAsyncWithAgeAndTimeout(TimeSpan::from(MAX_AGE), TimeSpan::from(TIMEOUT))
        .and_then(|finding| finding.join())
        .map_err(|error| {
            // E_ACCESSDENIED: the user, or Windows, said no.
            if error.code().0 as u32 == 0x8007_0005 {
                "denied"
            } else {
                "failed"
            }
        })?;
    let read = || -> windows::core::Result<(f64, f64, f64)> {
        let coordinate = fix.Coordinate()?;
        let position = coordinate.Point()?.Position()?;
        Ok((position.Latitude, position.Longitude, coordinate.Accuracy()?))
    };
    read().map_err(|_| "failed")
}

/// Opens Windows' location settings, where the user can let desktop apps
/// know where the PC is.
pub fn open_settings() {
    launch("ms-settings:privacy-location".to_string());
}

/// The only maps this opens: a place on OpenStreetMap, in the browser. The
/// app builds the address from numbers it checked; anything else is
/// refused, so this cannot be used to open some other site.
pub fn sound_map(url: &str) -> bool {
    let Some(rest) = url.strip_prefix("https://www.openstreetmap.org/?mlat=") else {
        return false;
    };
    rest.bytes()
        .all(|b| b.is_ascii_digit() || b"-.&=#/mlonap".contains(&b))
}

pub fn open_map(url: String) {
    launch(url);
}

fn launch(address: String) {
    thread::spawn(move || {
        let _ = Uri::CreateUri(&HSTRING::from(address)).and_then(|page| Launcher::LaunchUriAsync(&page));
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_map_of_a_place_is_opened() {
        assert!(sound_map("https://www.openstreetmap.org/?mlat=51.500729&mlon=-0.124625#map=17/51.500729/-0.124625"));
        for url in [
            "https://evil.example/?mlat=1&mlon=2",
            "http://www.openstreetmap.org/?mlat=1&mlon=2",
            "https://www.openstreetmap.org/?mlat=1&mlon=2&next=https://evil.example",
            "https://www.openstreetmap.org/?mlat=1 2",
            "file:///C:/Windows/System32/calc.exe",
        ] {
            assert!(!sound_map(url), "{url}");
        }
    }
}
