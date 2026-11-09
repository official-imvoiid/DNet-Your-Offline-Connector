//! The Windows Bluetooth calls.
//!
//! Windows reports everything on its own threads and every call that waits
//! for the radio blocks, so nothing here runs on the app's thread: the app
//! only leaves requests and collects events.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering::SeqCst};
use std::sync::mpsc::{channel, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::json;
use windows::core::{Error, IInspectable, Result, GUID, HRESULT, HSTRING};
use windows::Devices::Bluetooth::Advertisement::{
    BluetoothLEAdvertisementReceivedEventArgs, BluetoothLEAdvertisementWatcher, BluetoothLEScanningMode,
};
use windows::Devices::Bluetooth::GenericAttributeProfile::{
    GattCharacteristic, GattCharacteristicProperties, GattClientCharacteristicConfigurationDescriptorValue,
    GattCommunicationStatus, GattDeviceService, GattLocalCharacteristic, GattLocalCharacteristicParameters,
    GattProtectionLevel, GattServiceProvider, GattServiceProviderAdvertisingParameters, GattSession,
    GattValueChangedEventArgs, GattWriteOption, GattWriteRequestedEventArgs,
};
use windows::Devices::Bluetooth::{
    BluetoothAdapter, BluetoothCacheMode, BluetoothConnectionStatus, BluetoothError, BluetoothLEDevice,
};
use windows::Devices::Radios::RadioState;
use windows::Foundation::{Deferral, TypedEventHandler, Uri};
use windows::Security::Cryptography::CryptographicBuffer;
use windows::Storage::Streams::{DataReader, IBuffer};
use windows::System::Launcher;

use crate::{emit, lock, to_hex};

// Must match BleRadio.kt.
const SERVICE: GUID = GUID::from_u128(0xd0e7a1c0_5b1e_4f6a_9c3d_7e2b8a4f1d01);
/// Frames to a device are written here.
const RX: GUID = GUID::from_u128(0xd0e7a1c0_5b1e_4f6a_9c3d_7e2b8a4f1d02);
/// Frames from a device are notified here.
const TX: GUID = GUID::from_u128(0xd0e7a1c0_5b1e_4f6a_9c3d_7e2b8a4f1d03);

/// Bluetooth carries at most this much in one write or notification.
const MAX_FRAME: usize = 512;
const MIN_FRAME: usize = 20;
/// Connections this PC will start itself, leaving room for others to
/// connect in.
const MAX_OUTGOING: usize = 4;
const RETRY_AFTER: Duration = Duration::from_secs(5);
const LEAVE_ALONE: Duration = Duration::from_secs(300);
const CHECK_EVERY: Duration = Duration::from_secs(2);
/// How often a link's signal strength is passed on. Windows reports one
/// with every advertisement it hears, many a second.
const SIGNAL_EVERY: Duration = Duration::from_secs(2);

/// Whether it is time to pass on another signal strength for a link.
fn signal_due(last: Option<Instant>, now: Instant) -> bool {
    last.is_none_or(|last| now.duration_since(last) >= SIGNAL_EVERY)
}

/// How strongly the device at the other end of a link is heard, in dBm, as
/// the app is told it. A rough guide to how near it is. It says nothing
/// about which way.
fn signal_event(link: u32, rssi: i16) -> serde_json::Value {
    json!({ "t": "signal", "link": link, "rssi": rssi })
}

/// One frame of a link has gone. The app holds back what is less urgent
/// until there is room, so it is told each time.
fn sent_event(link: u32) -> serde_json::Value {
    json!({ "t": "sent", "link": link, "n": 1 })
}

/// True from `start` to `stop`, even while Bluetooth itself is off.
static WANTED: AtomicBool = AtomicBool::new(false);
/// Goes up at every start and stop, so a watcher left over from an earlier
/// start knows it is no longer the one in charge.
static GENERATION: AtomicU64 = AtomicU64::new(0);
/// Link numbers are never reused, so a late event cannot land on a newer
/// link.
static NEXT_LINK: AtomicU32 = AtomicU32::new(1);
static ACTIVE: Mutex<Option<Arc<Active>>> = Mutex::new(None);
static STATE: Mutex<&'static str> = Mutex::new("off");

enum End {
    /// This PC connected to them. The handles are kept so Windows keeps the
    /// connection.
    Outgoing { address: u64, device: BluetoothLEDevice, _tx: GattCharacteristic, _session: GattSession },
    /// They connected to this PC.
    Incoming { device_id: String },
}

struct Link {
    id: u32,
    max: usize,
    up: AtomicBool,
    /// Frames waiting to go out. A thread of the link's own sends them one
    /// at a time, in order, and ends when this is dropped.
    out: Mutex<Sender<Vec<u8>>>,
    end: End,
}

/// The radio while it is running.
struct Active {
    alive: AtomicBool,
    links: Mutex<HashMap<u32, Arc<Link>>>,
    /// Devices this PC is connecting to or connected to, by address.
    reaching: Mutex<HashSet<u64>>,
    /// Addresses not to connect to again until the given time.
    not_before: Mutex<HashMap<u64, Instant>>,
    /// Devices that connected to this PC, by the name Windows gives them.
    incoming: Mutex<HashMap<String, u32>>,
    /// Devices the app has turned away. Windows offers no way to disconnect
    /// one that connected in, so they are ignored until they leave.
    shunned: Mutex<HashSet<String>>,
    watcher: Mutex<Option<BluetoothLEAdvertisementWatcher>>,
    provider: Mutex<Option<GattServiceProvider>>,
    /// When each link's signal strength was last passed on.
    signalled: Mutex<HashMap<u32, Instant>>,
}

fn failed() -> Error {
    // E_FAIL
    Error::from_hresult(HRESULT(0x8000_4005_u32 as i32))
}

fn buffer(bytes: &[u8]) -> Result<IBuffer> {
    CryptographicBuffer::CreateFromByteArray(bytes)
}

fn read(buffer: &IBuffer) -> Result<Vec<u8>> {
    let mut bytes = vec![0u8; buffer.Length()? as usize];
    if !bytes.is_empty() {
        DataReader::FromBuffer(buffer)?.ReadBytes(&mut bytes)?;
    }
    Ok(bytes)
}

/// Three bytes of every packet are Bluetooth's own.
fn frame_size(packet: u16) -> usize {
    (packet as usize).saturating_sub(3).clamp(MIN_FRAME, MAX_FRAME)
}

fn characteristic(service: &GattDeviceService, uuid: GUID) -> Result<GattCharacteristic> {
    let found = service.GetCharacteristicsForUuidWithCacheModeAsync(uuid, BluetoothCacheMode::Uncached)?.join()?;
    if found.Status()? != GattCommunicationStatus::Success {
        return Err(failed());
    }
    found.Characteristics()?.GetAt(0)
}

fn report(state: &'static str) {
    let mut current = lock(&STATE);
    if *current != state {
        *current = state;
        emit(json!({ "t": "state", "state": state }));
    }
}

/// What stops the radio from running, with the adapter if nothing does.
fn obstacle() -> (&'static str, Option<BluetoothAdapter>) {
    let Ok(adapter) = BluetoothAdapter::GetDefaultAsync().and_then(|found| found.join()) else {
        return ("unsupported", None);
    };
    if !adapter.IsLowEnergySupported().unwrap_or(false) {
        return ("unsupported", None);
    }
    let on = adapter.GetRadioAsync().and_then(|found| found.join()).and_then(|radio| radio.State());
    match on {
        Ok(RadioState::On) => ("on", Some(adapter)),
        _ => ("bluetoothOff", None),
    }
}

pub fn start() {
    if WANTED.swap(true, SeqCst) {
        return;
    }
    let generation = GENERATION.fetch_add(1, SeqCst) + 1;
    let in_charge = move || WANTED.load(SeqCst) && GENERATION.load(SeqCst) == generation;
    // Bluetooth can be switched off and on while the app runs. Looking
    // every couple of seconds is how this notices either.
    thread::spawn(move || {
        while in_charge() {
            let (state, adapter) = obstacle();
            let state = match adapter {
                None => {
                    tear_down();
                    state
                }
                Some(adapter) => {
                    if lock(&ACTIVE).is_some() {
                        state
                    } else {
                        match Active::bring_up(&adapter) {
                            None => "unsupported",
                            Some(active) => {
                                let mut slot = lock(&ACTIVE);
                                if in_charge() && slot.is_none() {
                                    *slot = Some(active);
                                    state
                                } else {
                                    // Stopped while it was starting.
                                    drop(slot);
                                    active.shut();
                                    return;
                                }
                            }
                        }
                    }
                }
            };
            if in_charge() {
                report(state);
            }
            thread::sleep(CHECK_EVERY);
        }
    });
}

pub fn stop() {
    WANTED.store(false, SeqCst);
    GENERATION.fetch_add(1, SeqCst);
    tear_down();
    *lock(&STATE) = "off";
}

fn tear_down() {
    let active = lock(&ACTIVE).take();
    if let Some(active) = active {
        active.shut();
    }
}

pub fn send(id: u32, frames: Vec<Vec<u8>>) {
    let Some(active) = lock(&ACTIVE).clone() else { return };
    let Some(link) = lock(&active.links).get(&id).cloned() else { return };
    let out = lock(&link.out);
    for frame in frames {
        // Fails only if the link has just gone, which the app is told
        // about separately.
        let _ = out.send(frame);
    }
}

/// Ends one link and leaves that device alone for a while.
pub fn drop_link(id: u32) {
    let Some(active) = lock(&ACTIVE).clone() else { return };
    thread::spawn(move || active.shun(id));
}

/// Opens the Bluetooth page of Windows Settings. Switching Bluetooth on is
/// the user's to do.
pub fn open_settings() {
    thread::spawn(|| {
        let _ = Uri::CreateUri(&HSTRING::from("ms-settings:bluetooth")).and_then(|page| Launcher::LaunchUriAsync(&page));
    });
}

impl Active {
    /// Starts whichever halves this PC's Bluetooth can do. None if it can
    /// do neither.
    fn bring_up(adapter: &BluetoothAdapter) -> Option<Arc<Active>> {
        let active = Arc::new(Active {
            alive: AtomicBool::new(true),
            links: Mutex::default(),
            reaching: Mutex::default(),
            not_before: Mutex::default(),
            incoming: Mutex::default(),
            shunned: Mutex::default(),
            watcher: Mutex::default(),
            provider: Mutex::default(),
            signalled: Mutex::default(),
        });
        let found = adapter.IsPeripheralRoleSupported().unwrap_or(false) && active.be_found().is_ok();
        let finding = adapter.IsCentralRoleSupported().unwrap_or(false) && active.find_others().is_ok();
        if found || finding {
            Some(active)
        } else {
            active.shut();
            None
        }
    }

    fn shut(&self) {
        self.alive.store(false, SeqCst);
        if let Some(watcher) = lock(&self.watcher).take() {
            let _ = watcher.Stop();
        }
        if let Some(provider) = lock(&self.provider).take() {
            let _ = provider.StopAdvertising();
        }
        let ids: Vec<u32> = lock(&self.links).keys().copied().collect();
        for id in ids {
            self.lose(id);
        }
    }

    /// Tells the app a link exists. Once only.
    fn raise(&self, link: &Link) {
        if !self.alive.load(SeqCst) || !lock(&self.links).contains_key(&link.id) {
            return;
        }
        if !link.up.swap(true, SeqCst) {
            emit(json!({ "t": "up", "link": link.id, "max": link.max }));
        }
    }

    fn frame(&self, link: &Link, bytes: &[u8]) {
        // The other side may speak the moment it sees this PC ready, which
        // can be just before this PC hears that it is.
        self.raise(link);
        if link.up.load(SeqCst) {
            emit(json!({ "t": "frame", "link": link.id, "frame": to_hex(bytes) }));
        }
    }

    /// Forgets a link that has ended, and tells the app if it knew of it.
    fn lose(&self, id: u32) {
        let Some(link) = lock(&self.links).remove(&id) else { return };
        lock(&self.signalled).remove(&id);
        match &link.end {
            End::Outgoing { address, device, .. } => {
                lock(&self.reaching).remove(address);
                // Try that device again, but not at once.
                let until = Instant::now() + RETRY_AFTER;
                let mut not_before = lock(&self.not_before);
                let entry = not_before.entry(*address).or_insert(until);
                if *entry < until {
                    *entry = until;
                }
                let _ = device.Close();
            }
            End::Incoming { device_id } => {
                lock(&self.incoming).remove(device_id);
            }
        }
        if link.up.swap(false, SeqCst) {
            emit(json!({ "t": "down", "link": id }));
        }
    }

    fn shun(&self, id: u32) {
        let link = lock(&self.links).get(&id).cloned();
        if let Some(link) = link {
            match &link.end {
                End::Outgoing { address, .. } => {
                    lock(&self.not_before).insert(*address, Instant::now() + LEAVE_ALONE);
                }
                End::Incoming { device_id } => {
                    lock(&self.shunned).insert(device_id.clone());
                }
            }
        }
        self.lose(id);
    }

    // Being found: the half that others connect to.

    fn be_found(self: &Arc<Self>) -> Result<()> {
        let created = GattServiceProvider::CreateAsync(SERVICE)?.join()?;
        if created.Error()? != BluetoothError::Success {
            return Err(failed());
        }
        let provider = created.ServiceProvider()?;
        let service = provider.Service()?;

        let writable = GattLocalCharacteristicParameters::new()?;
        writable.SetCharacteristicProperties(GattCharacteristicProperties::Write)?;
        writable.SetWriteProtectionLevel(GattProtectionLevel::Plain)?;
        let rx = service.CreateCharacteristicAsync(RX, &writable)?.join()?.Characteristic()?;

        let notifying = GattLocalCharacteristicParameters::new()?;
        notifying.SetCharacteristicProperties(GattCharacteristicProperties::Notify)?;
        let tx = service.CreateCharacteristicAsync(TX, &notifying)?.join()?.Characteristic()?;

        // Windows hands over each write on whichever thread it likes. One
        // thread takes them in turn, so frames stay in the order they came.
        let (writes, arriving) = channel::<(GattWriteRequestedEventArgs, Deferral)>();
        let weak = Arc::downgrade(self);
        thread::spawn(move || {
            for (write, deferral) in arriving {
                if let Some(active) = weak.upgrade() {
                    let _ = active.written(&write);
                }
                let _ = deferral.Complete();
            }
        });
        let writes = Mutex::new(writes);
        rx.WriteRequested(&TypedEventHandler::<GattLocalCharacteristic, GattWriteRequestedEventArgs>::new(
            move |_, write| {
                let write = write.ok()?;
                let deferral = write.GetDeferral()?;
                let _ = lock(&writes).send((write.clone(), deferral));
                Ok(())
            },
        ))?;

        let weak = Arc::downgrade(self);
        tx.SubscribedClientsChanged(&TypedEventHandler::<GattLocalCharacteristic, IInspectable>::new(move |tx, _| {
            if let (Some(active), Some(tx)) = (weak.upgrade(), tx.as_ref()) {
                let _ = active.subscribers_changed(tx);
            }
            Ok(())
        }))?;

        let advertising = GattServiceProviderAdvertisingParameters::new()?;
        advertising.SetIsConnectable(true)?;
        advertising.SetIsDiscoverable(true)?;
        provider.StartAdvertisingWithParameters(&advertising)?;
        *lock(&self.provider) = Some(provider);
        Ok(())
    }

    /// A device wrote a frame to this PC.
    fn written(&self, write: &GattWriteRequestedEventArgs) -> Result<()> {
        let request = write.GetRequestAsync()?.join()?;
        let bytes = read(&request.Value()?)?;
        if request.Option()? == GattWriteOption::WriteWithResponse {
            request.Respond()?;
        }
        let device_id = write.Session()?.DeviceId()?.Id()?.to_string();
        let id = lock(&self.incoming).get(&device_id).copied();
        let link = id.and_then(|id| lock(&self.links).get(&id).cloned());
        // A write from a device that has not asked for notifications is
        // from one that is not ready, or not DNet. It is dropped.
        if let Some(link) = link {
            self.frame(&link, &bytes);
        }
        Ok(())
    }

    /// Asking for notifications is how another device says it is ready, and
    /// that is the moment a link exists. No longer asking ends it.
    fn subscribers_changed(self: &Arc<Self>, tx: &GattLocalCharacteristic) -> Result<()> {
        let clients = tx.SubscribedClients()?;
        let mut present = HashMap::new();
        for index in 0..clients.Size()? {
            let client = clients.GetAt(index)?;
            present.insert(client.Session()?.DeviceId()?.Id()?.to_string(), client);
        }

        let gone: Vec<u32> =
            lock(&self.incoming).iter().filter(|(device, _)| !present.contains_key(*device)).map(|(_, id)| *id).collect();
        for id in gone {
            self.lose(id);
        }
        lock(&self.shunned).retain(|device| present.contains_key(device));

        for (device_id, client) in present {
            if lock(&self.incoming).contains_key(&device_id) || lock(&self.shunned).contains(&device_id) {
                continue;
            }
            let id = NEXT_LINK.fetch_add(1, SeqCst);
            let (out, waiting) = channel::<Vec<u8>>();
            let link = Arc::new(Link {
                id,
                max: frame_size(client.Session()?.MaxPduSize()?),
                up: AtomicBool::new(false),
                out: Mutex::new(out),
                end: End::Incoming { device_id: device_id.clone() },
            });
            lock(&self.links).insert(id, link.clone());
            lock(&self.incoming).insert(device_id, id);

            let weak = Arc::downgrade(self);
            let tx = tx.clone();
            thread::spawn(move || {
                for frame in waiting {
                    let sent = buffer(&frame)
                        .and_then(|frame| tx.NotifyValueForSubscribedClientAsync(&frame, &client)?.join())
                        .and_then(|result| result.Status());
                    if sent != Ok(GattCommunicationStatus::Success) {
                        if let Some(active) = weak.upgrade() {
                            active.lose(id);
                        }
                        break;
                    }
                    emit(sent_event(id));
                }
            });
            self.raise(&link);
        }
        Ok(())
    }

    // Finding others: the half that connects out.

    fn find_others(self: &Arc<Self>) -> Result<()> {
        let watcher = BluetoothLEAdvertisementWatcher::new()?;
        watcher.AdvertisementFilter()?.Advertisement()?.ServiceUuids()?.Append(SERVICE)?;
        watcher.SetScanningMode(BluetoothLEScanningMode::Active)?;
        let weak = Arc::downgrade(self);
        watcher.Received(&TypedEventHandler::<
            BluetoothLEAdvertisementWatcher,
            BluetoothLEAdvertisementReceivedEventArgs,
        >::new(move |_, seen| {
            if let (Some(active), Some(seen)) = (weak.upgrade(), seen.as_ref()) {
                let address = seen.BluetoothAddress()?;
                if let Ok(rssi) = seen.RawSignalStrengthInDBm() {
                    active.heard(address, rssi);
                }
                active.found(address);
            }
            Ok(())
        }))?;
        watcher.Start()?;
        *lock(&self.watcher) = Some(watcher);
        Ok(())
    }

    /// Passes on how strongly a device this PC is connected to is heard.
    /// Only for links this PC started: a device that connected in shows
    /// up under a name, not an address, and its sightings cannot be told
    /// apart from anyone else's.
    fn heard(&self, address: u64, rssi: i16) {
        let link = lock(&self.links).values().find_map(|link| match &link.end {
            End::Outgoing { address: at, .. } if *at == address && link.up.load(SeqCst) => Some(link.id),
            _ => None,
        });
        let Some(link) = link else {
            return;
        };
        let now = Instant::now();
        {
            let mut signalled = lock(&self.signalled);
            if !signal_due(signalled.get(&link).copied(), now) {
                return;
            }
            signalled.insert(link, now);
        }
        emit(signal_event(link, rssi));
    }

    fn found(self: &Arc<Self>, address: u64) {
        if !self.alive.load(SeqCst) {
            return;
        }
        {
            let mut reaching = lock(&self.reaching);
            if reaching.contains(&address) || reaching.len() >= MAX_OUTGOING {
                return;
            }
            if lock(&self.not_before).get(&address).is_some_and(|until| Instant::now() < *until) {
                return;
            }
            reaching.insert(address);
        }
        let active = self.clone();
        thread::spawn(move || {
            if active.connect(address).is_err() {
                lock(&active.reaching).remove(&address);
                lock(&active.not_before).insert(address, Instant::now() + RETRY_AFTER);
            }
        });
    }

    fn connect(self: &Arc<Self>, address: u64) -> Result<()> {
        let device = BluetoothLEDevice::FromBluetoothAddressAsync(address)?.join()?;
        let found = device.GetGattServicesForUuidWithCacheModeAsync(SERVICE, BluetoothCacheMode::Uncached)?.join()?;
        if found.Status()? != GattCommunicationStatus::Success {
            return Err(failed());
        }
        let service = found.Services()?.GetAt(0)?;
        let rx = characteristic(&service, RX)?;
        let tx = characteristic(&service, TX)?;
        let session = GattSession::FromDeviceIdAsync(&device.BluetoothDeviceId()?)?.join()?;
        session.SetMaintainConnection(true)?;

        let id = NEXT_LINK.fetch_add(1, SeqCst);
        let (out, waiting) = channel::<Vec<u8>>();
        let link = Arc::new(Link {
            id,
            max: frame_size(session.MaxPduSize()?),
            up: AtomicBool::new(false),
            out: Mutex::new(out),
            end: End::Outgoing { address, device: device.clone(), _tx: tx.clone(), _session: session },
        });
        if !self.alive.load(SeqCst) {
            return Err(failed());
        }
        lock(&self.links).insert(id, link.clone());

        let (weak, weak_link) = (Arc::downgrade(self), Arc::downgrade(&link));
        tx.ValueChanged(&TypedEventHandler::<GattCharacteristic, GattValueChangedEventArgs>::new(move |_, changed| {
            if let (Some(active), Some(link), Some(changed)) = (weak.upgrade(), weak_link.upgrade(), changed.as_ref()) {
                active.frame(&link, &read(&changed.CharacteristicValue()?)?);
            }
            Ok(())
        }))?;

        let weak = Arc::downgrade(self);
        device.ConnectionStatusChanged(&TypedEventHandler::<BluetoothLEDevice, IInspectable>::new(move |device, _| {
            if let (Some(active), Some(device)) = (weak.upgrade(), device.as_ref()) {
                if device.ConnectionStatus()? == BluetoothConnectionStatus::Disconnected {
                    active.lose(id);
                }
            }
            Ok(())
        }))?;

        // Asking for notifications tells the other device this one is
        // ready.
        let asked = tx
            .WriteClientCharacteristicConfigurationDescriptorAsync(
                GattClientCharacteristicConfigurationDescriptorValue::Notify,
            )
            .and_then(|asking| asking.join());
        if asked != Ok(GattCommunicationStatus::Success) {
            self.lose(id);
            return Err(failed());
        }

        let weak = Arc::downgrade(self);
        thread::spawn(move || {
            for frame in waiting {
                let sent = buffer(&frame)
                    .and_then(|frame| rx.WriteValueWithResultAsync(&frame)?.join())
                    .and_then(|result| result.Status());
                if sent != Ok(GattCommunicationStatus::Success) {
                    if let Some(active) = weak.upgrade() {
                        active.lose(id);
                    }
                    break;
                }
                emit(sent_event(id));
            }
        });
        self.raise(&link);
        Ok(())
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_signal_strength_is_passed_on_now_and_then_not_with_every_sighting() {
        let start = Instant::now();
        assert!(signal_due(None, start));
        assert!(!signal_due(Some(start), start + Duration::from_millis(500)));
        assert!(signal_due(Some(start), start + SIGNAL_EVERY));
    }

    #[test]
    fn a_frame_gone_is_told_to_the_app_as_the_phone_tells_it() {
        assert_eq!(sent_event(4), json!({"t": "sent", "link": 4, "n": 1}));
    }

    #[test]
    fn a_signal_strength_is_told_to_the_app_as_the_phone_tells_it() {
        assert_eq!(
            signal_event(7, -63),
            json!({"t": "signal", "link": 7, "rssi": -63})
        );
    }
}
