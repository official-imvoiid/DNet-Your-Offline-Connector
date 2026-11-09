//! Wi-Fi Direct on Windows: a small Wi-Fi network this PC makes for a
//! phone to join, so that a big file need not crawl over Bluetooth. It
//! needs no router, no hotspot and no internet, and the PC stays on
//! whatever Wi-Fi it was already using.
//!
//! The group is only a road. This library does not know who joins or what
//! is sent: the app gives the group a name and password it made up, tells
//! them to one person over a link that is already sealed, and everything
//! that then travels on the group is sealed by the core as it is over
//! Bluetooth.
//!
//! A PC makes a group and does not join one. Joining would take it off
//! the Wi-Fi it is on.
//!
//! Not yet verified on devices.

use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;

use serde_json::{json, Value};
use windows::core::{Result, HSTRING};
use windows::Devices::WiFiDirect::{
    WiFiDirectAdvertisementPublisher, WiFiDirectAdvertisementPublisherStatus,
    WiFiDirectAdvertisementPublisherStatusChangedEventArgs, WiFiDirectConnectionListener,
    WiFiDirectConnectionRequestedEventArgs, WiFiDirectDevice,
};
use windows::Foundation::TypedEventHandler;
use windows::Security::Credentials::PasswordCredential;

use crate::lock;

struct Group {
    /// Which making of a group this is. One that was given up must not
    /// speak for the next.
    turn: u32,
    /// "off", "starting" or "on".
    state: &'static str,
    /// The addresses, on the group's network, of the devices let in.
    members: Vec<String>,
    /// Tells the thread holding the group to let it go.
    stop: Option<Sender<()>>,
}

static GROUP: Mutex<Group> = Mutex::new(Group { turn: 0, state: "off", members: Vec::new(), stop: None });

/// Whether these could be a group the app made, and its password. The same
/// rule the core applies before it will offer or take one.
pub fn sound(network: &str, pass: &str) -> bool {
    let plain = |text: &str| text.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-');
    let tag = network.strip_prefix("DIRECT-").unwrap_or_default().as_bytes();
    network.len() <= 32
        && tag.len() >= 2
        && tag[..2].iter().all(u8::is_ascii_alphanumeric)
        && plain(network)
        && (8..=63).contains(&pass.len())
        && pass.bytes().all(|b| b.is_ascii_alphanumeric())
}

/// Starts making a group. Whether it worked shows in [`state`] a moment
/// later: Windows answers in its own time.
pub fn host(network: String, pass: String) {
    stop();
    let (tell, told) = channel();
    let turn = {
        let mut group = lock(&GROUP);
        group.turn += 1;
        group.state = "starting";
        group.stop = Some(tell);
        group.turn
    };
    // Everything Windows hands over for the group is kept by this thread,
    // and goes when it ends.
    thread::spawn(move || {
        if hold(&network, &pass, turn, told).is_err() {
            set(turn, "off");
        }
    });
}

/// Gives the group up, if there is one.
pub fn stop() {
    let mut group = lock(&GROUP);
    group.turn += 1;
    group.state = "off";
    group.members.clear();
    if let Some(stop) = group.stop.take() {
        let _ = stop.send(());
    }
}

pub fn state() -> Value {
    let group = lock(&GROUP);
    json!({ "state": group.state, "members": group.members })
}

fn set(turn: u32, state: &'static str) {
    let mut group = lock(&GROUP);
    if group.turn != turn {
        return;
    }
    group.state = state;
    if state == "off" {
        group.members.clear();
        // Wakes the thread holding the group, which then lets it go.
        group.stop = None;
    }
}

/// Makes the group and keeps it until told to stop.
fn hold(network: &str, pass: &str, turn: u32, told: Receiver<()>) -> Result<()> {
    let publisher = WiFiDirectAdvertisementPublisher::new()?;
    let advertisement = publisher.Advertisement()?;
    // This PC is the one the other device joins.
    advertisement.SetIsAutonomousGroupOwnerEnabled(true)?;
    // "Legacy" is Windows' word for a group that can be joined with a name
    // and a password, which is how a phone joins this one.
    let legacy = advertisement.LegacySettings()?;
    legacy.SetIsEnabled(true)?;
    legacy.SetSsid(&HSTRING::from(network))?;
    let credential = PasswordCredential::new()?;
    credential.SetPassword(&HSTRING::from(pass))?;
    legacy.SetPassphrase(&credential)?;

    // The devices let in. Kept, because letting go of one shuts it out.
    let inside: Arc<Mutex<Vec<WiFiDirectDevice>>> = Arc::default();
    let keep = inside.clone();
    let listener = WiFiDirectConnectionListener::new()?;
    listener.ConnectionRequested(&TypedEventHandler::<
        WiFiDirectConnectionListener,
        WiFiDirectConnectionRequestedEventArgs,
    >::new(move |_, asked| {
        // A group is made for one person, so one device is let in and no
        // more. This is a Wi-Fi Direct request to pair, which a device can
        // make without the password; a phone joining by name and password
        // as DNet's do may not come this way at all. Whoever does come in
        // still has to prove who they are before anything is sent to them.
        if !lock(&keep).is_empty() {
            return Ok(());
        }
        let request = asked.ok()?.GetConnectionRequest()?;
        let device = WiFiDirectDevice::FromIdAsync(&request.DeviceInformation()?.Id()?)?.join()?;
        let mut addresses = Vec::new();
        for pair in device.GetConnectionEndpointPairs()? {
            addresses.push(pair.RemoteHostName()?.CanonicalName()?.to_string());
        }
        lock(&keep).push(device);
        let mut group = lock(&GROUP);
        if group.turn == turn {
            group.members.extend(addresses);
        }
        Ok(())
    }))?;
    publisher.StatusChanged(&TypedEventHandler::<
        WiFiDirectAdvertisementPublisher,
        WiFiDirectAdvertisementPublisherStatusChangedEventArgs,
    >::new(move |_, changed| {
        let status = changed.ok()?.Status()?;
        if status == WiFiDirectAdvertisementPublisherStatus::Started {
            set(turn, "on");
        } else if status == WiFiDirectAdvertisementPublisherStatus::Aborted {
            // No Wi-Fi, or a Wi-Fi card that cannot do this.
            set(turn, "off");
        }
        Ok(())
    }))?;
    publisher.Start()?;

    // Until told to stop, or until there is nobody left to tell it.
    let _ = told.recv();
    let _ = publisher.Stop();
    lock(&inside).clear();
    drop(listener);
    Ok(())
}
