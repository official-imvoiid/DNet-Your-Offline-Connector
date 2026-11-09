//! Everything that can go wrong inside the core.

#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    #[error("the core has not been opened")]
    NotOpen,
    #[error("{0}")]
    Invalid(String),
    #[error("an identity already exists")]
    AlreadyExists,
    #[error("the key does not open this data")]
    WrongKey,
    #[error("this person has not accepted a chat request")]
    NotAContact,
    #[error("this data was made by a newer version of the app (format {found}, this app reads up to {supported})")]
    NewerVersion { found: u32, supported: u32 },
    #[error("stored data is damaged: {0}")]
    Corrupt(String),
    #[error("storage failed: {0}")]
    Storage(String),
    #[error("the system could not provide random numbers")]
    Random,
    #[error("the system could not protect the key: {0}")]
    KeyGuard(String),
}

impl CoreError {
    /// A short stable name the app can switch on. The message is for logs.
    pub fn code(&self) -> &'static str {
        match self {
            CoreError::NotOpen => "not_open",
            CoreError::Invalid(_) => "invalid",
            CoreError::AlreadyExists => "already_exists",
            CoreError::WrongKey => "wrong_key",
            CoreError::NotAContact => "not_a_contact",
            CoreError::NewerVersion { .. } => "newer_version",
            CoreError::Corrupt(_) => "corrupt",
            CoreError::Storage(_) => "storage",
            CoreError::Random => "random",
            CoreError::KeyGuard(_) => "key_guard",
        }
    }
}

pub type Result<T> = std::result::Result<T, CoreError>;

macro_rules! storage_error {
    ($($t:ty),*) => {$(
        impl From<$t> for CoreError {
            fn from(e: $t) -> Self {
                CoreError::Storage(e.to_string())
            }
        }
    )*};
}
storage_error!(
    redb::DatabaseError,
    redb::TransactionError,
    redb::TableError,
    redb::StorageError,
    redb::CommitError,
    std::io::Error
);
