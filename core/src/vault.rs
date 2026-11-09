//! Encrypted storage on the device.
//!
//! Records live in one `redb` database file. `redb` commits each write as a
//! whole or not at all, so a crash or a dead battery cannot leave a record
//! half written.
//!
//! What is encrypted: every record's content, with AES-256-GCM.
//! What is not: a record's group name and id, and how many records there are
//! and how long each is. Ids must therefore be meaningless on their own.

use std::path::{Path, PathBuf};

use redb::{Database, ReadableDatabase, ReadableTable, TableDefinition, WriteTransaction};
use zeroize::Zeroizing;

use crate::error::{CoreError, Result};
use crate::seal;

/// The format this version of the app reads and writes.
pub const SCHEMA_VERSION: u32 = 1;

const FILE_NAME: &str = "vault.redb";
const RECORDS: TableDefinition<&[u8], &[u8]> = TableDefinition::new("records");
const META: TableDefinition<&str, &[u8]> = TableDefinition::new("meta");
const META_SCHEMA: &str = "schema";
const META_CHECK: &str = "check";
/// Sealed at creation and opened on every start, to tell a wrong key from
/// an empty vault.
const CHECK_PLAINTEXT: &[u8] = b"dnet vault";
const CHECK_CONTEXT: &[u8] = b"dnet vault key check";

pub struct Vault {
    db: Database,
    key: Zeroizing<[u8; 32]>,
}

/// A record's place in the table: one length byte, the group, then the id.
fn record_key(group: &str, id: &[u8]) -> Result<Vec<u8>> {
    let length = u8::try_from(group.len())
        .map_err(|_| CoreError::Invalid("group name is too long".into()))?;
    let mut key = Vec::with_capacity(1 + group.len() + id.len());
    key.push(length);
    key.extend_from_slice(group.as_bytes());
    key.extend_from_slice(id);
    Ok(key)
}

impl Vault {
    fn file(dir: &Path) -> PathBuf {
        dir.join(FILE_NAME)
    }

    pub fn exists(dir: &Path) -> bool {
        Self::file(dir).exists()
    }

    /// Opens the vault in `dir`, creating it if there is none.
    ///
    /// Fails with [`CoreError::WrongKey`] if `key` is not the key the vault
    /// was made with, and with [`CoreError::NewerVersion`] if a newer app
    /// wrote it. Neither failure changes the file.
    pub fn open(dir: &Path, key: &[u8; 32]) -> Result<Self> {
        std::fs::create_dir_all(dir)?;
        let db = Database::create(Self::file(dir))?;
        let vault = Self {
            db,
            key: Zeroizing::new(*key),
        };

        let tx = vault.db.begin_write()?;
        {
            let mut meta = tx.open_table(META)?;
            let check = meta.get(META_CHECK)?.map(|v| v.value().to_vec());
            match check {
                None => {
                    meta.insert(
                        META_CHECK,
                        seal::seal(key, CHECK_CONTEXT, CHECK_PLAINTEXT)?.as_slice(),
                    )?;
                    meta.insert(META_SCHEMA, SCHEMA_VERSION.to_le_bytes().as_slice())?;
                }
                Some(sealed) => {
                    seal::open(key, CHECK_CONTEXT, &sealed)?;
                    let found = read_schema(meta.get(META_SCHEMA)?.map(|v| v.value().to_vec()))?;
                    if found > SCHEMA_VERSION {
                        return Err(CoreError::NewerVersion {
                            found,
                            supported: SCHEMA_VERSION,
                        });
                    }
                    // Migrations go here, one step per version, inside this
                    // transaction so a failed step leaves the old format.
                    // There are none yet: version 1 is the first format.
                    if found < SCHEMA_VERSION {
                        meta.insert(META_SCHEMA, SCHEMA_VERSION.to_le_bytes().as_slice())?;
                    }
                }
            }
            // Make sure the table exists, so reads never have to create it.
            tx.open_table(RECORDS)?;
        }
        tx.commit()?;
        Ok(vault)
    }

    pub fn schema_version(&self) -> Result<u32> {
        let tx = self.db.begin_read()?;
        let meta = tx.open_table(META)?;
        read_schema(meta.get(META_SCHEMA)?.map(|v| v.value().to_vec()))
    }

    /// Only for tests of the version check.
    #[doc(hidden)]
    pub fn set_schema_version_for_test(&self, version: u32) -> Result<()> {
        let tx = self.db.begin_write()?;
        tx.open_table(META)?
            .insert(META_SCHEMA, version.to_le_bytes().as_slice())?;
        tx.commit()?;
        Ok(())
    }

    pub fn get(&self, group: &str, id: &[u8]) -> Result<Option<Vec<u8>>> {
        let key = record_key(group, id)?;
        let tx = self.db.begin_read()?;
        let table = tx.open_table(RECORDS)?;
        let sealed = table.get(key.as_slice())?.map(|v| v.value().to_vec());
        match sealed {
            None => Ok(None),
            Some(sealed) => Ok(Some(open_record(&self.key, &key, &sealed)?)),
        }
    }

    /// Every record in `group`, in order of id.
    pub fn list(&self, group: &str) -> Result<Vec<(Vec<u8>, Vec<u8>)>> {
        self.list_prefix(group, b"")
    }

    /// The records in `group` whose id starts with `id_prefix`, in order of
    /// id. Each comes back with its whole id.
    pub fn list_prefix(&self, group: &str, id_prefix: &[u8]) -> Result<Vec<(Vec<u8>, Vec<u8>)>> {
        let group_prefix = record_key(group, b"")?;
        let prefix = record_key(group, id_prefix)?;
        let tx = self.db.begin_read()?;
        let table = tx.open_table(RECORDS)?;
        let mut records = Vec::new();
        for entry in table.range::<&[u8]>(prefix.as_slice()..)? {
            let (key, sealed) = entry?;
            let key = key.value();
            if !key.starts_with(&prefix) {
                break;
            }
            records.push((
                key[group_prefix.len()..].to_vec(),
                open_record(&self.key, key, sealed.value())?,
            ));
        }
        Ok(records)
    }

    pub fn put(&self, group: &str, id: &[u8], value: &[u8]) -> Result<()> {
        self.batch(|tx| tx.put(group, id, value))
    }

    pub fn delete(&self, group: &str, id: &[u8]) -> Result<()> {
        self.batch(|tx| tx.delete(group, id))
    }

    /// Runs several writes as one. If `work` returns an error, none of them
    /// happen.
    pub fn batch<T>(&self, work: impl FnOnce(&mut Batch) -> Result<T>) -> Result<T> {
        let mut batch = Batch {
            tx: self.db.begin_write()?,
            key: &self.key,
        };
        let value = work(&mut batch)?;
        batch.tx.commit()?;
        Ok(value)
    }

    /// Deletes the vault's file. The vault must not be open.
    pub fn destroy(dir: &Path) -> Result<()> {
        match std::fs::remove_file(Self::file(dir)) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e.into()),
        }
    }
}

/// Writes that commit together.
pub struct Batch<'a> {
    tx: WriteTransaction,
    key: &'a [u8; 32],
}

impl Batch<'_> {
    pub fn put(&mut self, group: &str, id: &[u8], value: &[u8]) -> Result<()> {
        let key = record_key(group, id)?;
        // Bound to its own place, so a sealed record copied over another
        // one does not open.
        let sealed = seal::seal(self.key, &key, value)?;
        self.tx
            .open_table(RECORDS)?
            .insert(key.as_slice(), sealed.as_slice())?;
        Ok(())
    }

    pub fn delete(&mut self, group: &str, id: &[u8]) -> Result<()> {
        let key = record_key(group, id)?;
        self.tx.open_table(RECORDS)?.remove(key.as_slice())?;
        Ok(())
    }
}

fn open_record(key: &[u8; 32], record_key: &[u8], sealed: &[u8]) -> Result<Vec<u8>> {
    // The key was checked when the vault opened, so a record that fails
    // here was damaged or moved, not locked with another key.
    seal::open(key, record_key, sealed)
        .map(|plain| plain.to_vec())
        .map_err(|_| CoreError::Corrupt("a stored record does not open".into()))
}

fn read_schema(bytes: Option<Vec<u8>>) -> Result<u32> {
    let bytes =
        bytes.ok_or_else(|| CoreError::Corrupt("the vault has no format version".into()))?;
    let bytes: [u8; 4] = bytes
        .as_slice()
        .try_into()
        .map_err(|_| CoreError::Corrupt("the vault's format version is unreadable".into()))?;
    Ok(u32::from_le_bytes(bytes))
}
