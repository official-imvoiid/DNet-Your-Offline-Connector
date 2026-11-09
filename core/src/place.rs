//! A place on Earth that someone chose to send: where their device found
//! itself when they asked. It travels sealed and signed like any message;
//! nothing here looks it up or goes online.

use serde::{Deserialize, Serialize};

/// The furthest off a place may be said to be and still be sent: 100 km.
/// A device that knows no better than that does not know where it is.
const MAX_ACCURACY: u32 = 100_000;

/// Degrees north and east, and how far off the device said it might be,
/// in metres. Nought metres: the device did not say.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct Place {
    pub lat: f64,
    pub lon: f64,
    #[serde(default)]
    pub accuracy: u32,
}

impl Place {
    /// The place, if it is one: on the globe and found to within 100 km.
    /// Kept to six decimal places, about a tenth of a metre, which is
    /// finer than any phone can tell.
    pub fn checked(self) -> Option<Place> {
        let on_globe = self.lat.is_finite()
            && self.lon.is_finite()
            && (-90.0..=90.0).contains(&self.lat)
            && (-180.0..=180.0).contains(&self.lon);
        (on_globe && self.accuracy <= MAX_ACCURACY).then(|| Place {
            lat: round6(self.lat),
            lon: round6(self.lon),
            accuracy: self.accuracy,
        })
    }

    /// The place in words, as an app that does not know places shows it:
    /// "51.500700, -0.124600".
    pub fn text(&self) -> String {
        format!("{:.6}, {:.6}", self.lat, self.lon)
    }
}

fn round6(degrees: f64) -> f64 {
    let rounded = (degrees * 1e6).round() / 1e6;
    // Never "-0.000000".
    if rounded == 0.0 {
        0.0
    } else {
        rounded
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(lat: f64, lon: f64, accuracy: u32) -> Place {
        Place { lat, lon, accuracy }
    }

    #[test]
    fn a_place_on_the_globe_is_kept_to_six_places() {
        let place = at(51.500_729_4, -0.124_625_1, 12).checked().unwrap();
        assert_eq!(place, at(51.500_729, -0.124_625, 12));
        assert_eq!(place.text(), "51.500729, -0.124625");
        assert_eq!(
            at(-0.000_000_1, 0.0, 0).checked().unwrap().text(),
            "0.000000, 0.000000"
        );
    }

    #[test]
    fn the_poles_and_the_date_line_are_places() {
        for place in [at(90.0, 180.0, 5), at(-90.0, -180.0, 5)] {
            assert!(place.checked().is_some());
        }
    }

    #[test]
    fn what_is_not_on_the_globe_is_not_a_place() {
        for place in [
            at(90.5, 0.0, 5),
            at(-91.0, 0.0, 5),
            at(0.0, 180.01, 5),
            at(0.0, -200.0, 5),
            at(f64::NAN, 0.0, 5),
            at(0.0, f64::INFINITY, 5),
            at(10.0, 10.0, MAX_ACCURACY + 1),
        ] {
            assert!(place.checked().is_none(), "{place:?}");
        }
    }

    #[test]
    fn it_reads_as_it_is_written() {
        let place: Place =
            serde_json::from_str(r#"{"lat":1.5,"lon":-2.25,"accuracy":30}"#).unwrap();
        assert_eq!(place, at(1.5, -2.25, 30));
        let unsure: Place = serde_json::from_str(r#"{"lat":1.5,"lon":-2.25}"#).unwrap();
        assert_eq!(unsure.accuracy, 0);
        // Metres are whole numbers.
        assert!(serde_json::from_str::<Place>(r#"{"lat":1,"lon":2,"accuracy":1.5}"#).is_err());
    }
}
