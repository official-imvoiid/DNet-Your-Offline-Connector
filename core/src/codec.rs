//! Squeezes speech for calls: IMA ADPCM, four bits a sample.
//!
//! Sound comes in as 16-bit samples, 16,000 a second, one channel: 32 KB
//! every second. This makes that a quarter of the size, which is plenty
//! small for a Wi-Fi link, and keeps speech clear. It is an old, simple,
//! well-known scheme with no licence attached, and both kinds of device
//! use this one copy of it.
//!
//! Each block carries the state it starts from, so a block can be heard
//! without the ones before it. A block lost on the way costs that block
//! and nothing more.

/// Samples a second.
pub const RATE: usize = 16_000;

/// How much a step can change, for each 4-bit code.
const INDEX_TABLE: [i32; 16] = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8];

const STEP_TABLE: [i32; 89] = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66,
    73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449,
    494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272,
    2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493,
    10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
];

/// The most samples one block holds: a tenth of a second. Calls send a
/// fiftieth.
pub const MAX_SAMPLES: usize = RATE / 10;

/// The bytes before the codes: where the block starts (two bytes) and the
/// step it starts on (one), and one spare.
const HEADER: usize = 4;

/// Where a block starts from: the sample it predicts from, and how big a
/// step is.
#[derive(Clone, Copy, Default)]
struct State {
    predicted: i32,
    index: i32,
}

impl State {
    /// Moves on by one code and returns the sample it stands for.
    fn step(&mut self, code: u8) -> i16 {
        let step = STEP_TABLE[self.index as usize];
        let mut change = step >> 3;
        if code & 4 != 0 {
            change += step;
        }
        if code & 2 != 0 {
            change += step >> 1;
        }
        if code & 1 != 0 {
            change += step >> 2;
        }
        if code & 8 != 0 {
            self.predicted -= change;
        } else {
            self.predicted += change;
        }
        self.predicted = self.predicted.clamp(i16::MIN as i32, i16::MAX as i32);
        self.index = (self.index + INDEX_TABLE[code as usize]).clamp(0, 88);
        self.predicted as i16
    }

    /// The code that comes nearest to `sample` from here.
    fn code_for(&self, sample: i16) -> u8 {
        let mut step = STEP_TABLE[self.index as usize];
        let mut difference = sample as i32 - self.predicted;
        let mut code = 0u8;
        if difference < 0 {
            code = 8;
            difference = -difference;
        }
        if difference >= step {
            code |= 4;
            difference -= step;
        }
        step >>= 1;
        if difference >= step {
            code |= 2;
            difference -= step;
        }
        step >>= 1;
        if difference >= step {
            code |= 1;
        }
        code
    }
}

/// Squeezes `samples`, each little-endian 16-bit, into one block. Empty
/// for nothing, or for more than [`MAX_SAMPLES`].
///
/// Each block starts from the first sample, so a block stands on its own.
pub fn encode(pcm: &[u8]) -> Vec<u8> {
    let samples: Vec<i16> = pcm
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| i16::from_le_bytes(*pair))
        .collect();
    if samples.is_empty() || samples.len() > MAX_SAMPLES {
        return Vec::new();
    }
    let mut state = State {
        predicted: samples[0] as i32,
        index: start_index(&samples),
    };
    let mut block = Vec::with_capacity(HEADER + samples.len().div_ceil(2));
    block.extend_from_slice(&(state.predicted as i16).to_le_bytes());
    block.push(state.index as u8);
    block.push(0);
    for pair in samples.chunks(2) {
        let low = state.code_for(pair[0]);
        state.step(low);
        let high = match pair.get(1) {
            Some(&sample) => {
                let code = state.code_for(sample);
                state.step(code);
                code
            }
            None => 0,
        };
        block.push(low | (high << 4));
    }
    block
}

/// A first step near the size of the sound, so a loud block does not
/// spend its first few samples catching up.
fn start_index(samples: &[i16]) -> i32 {
    let first = samples[0] as i32;
    let jump = samples
        .iter()
        .take(8)
        .map(|&s| (s as i32 - first).abs())
        .max()
        .unwrap_or(0);
    STEP_TABLE
        .iter()
        .position(|&step| step >= jump / 4)
        .unwrap_or(88) as i32
}

/// Undoes [`encode`]: `samples` 16-bit little-endian samples. None if the
/// block is not one.
pub fn decode(block: &[u8], samples: usize) -> Option<Vec<u8>> {
    if block.len() < HEADER
        || samples == 0
        || samples > MAX_SAMPLES
        || block.len() != HEADER + samples.div_ceil(2)
        || block[2] > 88
    {
        return None;
    }
    let mut state = State {
        predicted: i16::from_le_bytes([block[0], block[1]]) as i32,
        index: block[2] as i32,
    };
    let mut pcm = Vec::with_capacity(samples * 2);
    for (i, &byte) in block[HEADER..].iter().enumerate() {
        pcm.extend_from_slice(&state.step(byte & 15).to_le_bytes());
        if i * 2 + 1 < samples {
            pcm.extend_from_slice(&state.step(byte >> 4).to_le_bytes());
        }
    }
    Some(pcm)
}

/// How loud the samples are, from 0 (silence) to 1 (as loud as can be
/// held): the root mean square, so a click does not count as speech.
pub fn level(pcm: &[u8]) -> f64 {
    let mut sum = 0f64;
    let mut count = 0usize;
    for pair in pcm.as_chunks::<2>().0 {
        let sample = i16::from_le_bytes(*pair) as f64 / 32768.0;
        sum += sample * sample;
        count += 1;
    }
    if count == 0 {
        0.0
    } else {
        (sum / count as f64).sqrt()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(samples: usize, loudness: f64) -> Vec<u8> {
        (0..samples)
            .flat_map(|i| {
                let t = i as f64 / RATE as f64;
                let value = (2.0 * std::f64::consts::PI * 440.0 * t).sin() * loudness * 32767.0;
                (value as i16).to_le_bytes()
            })
            .collect()
    }

    fn samples(pcm: &[u8]) -> Vec<i32> {
        pcm.as_chunks::<2>()
            .0
            .iter()
            .map(|p| i16::from_le_bytes(*p) as i32)
            .collect()
    }

    #[test]
    fn a_block_is_a_quarter_of_the_size() {
        let pcm = tone(320, 0.5);
        assert_eq!(pcm.len(), 640);
        assert_eq!(encode(&pcm).len(), 4 + 160);
    }

    #[test]
    fn speech_comes_back_close_to_what_went_in() {
        let pcm = tone(320, 0.5);
        let back = decode(&encode(&pcm), 320).unwrap();
        assert_eq!(back.len(), pcm.len());
        let (a, b) = (samples(&pcm), samples(&back));
        // The error is small next to the sound itself.
        let noise: f64 = a
            .iter()
            .zip(&b)
            .map(|(x, y)| ((x - y) as f64).powi(2))
            .sum();
        let signal: f64 = a.iter().map(|x| (*x as f64).powi(2)).sum();
        assert!(signal / noise > 100.0, "signal to noise {}", signal / noise);
    }

    #[test]
    fn silence_stays_silent() {
        let pcm = vec![0u8; 640];
        let back = decode(&encode(&pcm), 320).unwrap();
        assert!(samples(&back).iter().all(|s| s.abs() < 8));
    }

    #[test]
    fn an_odd_number_of_samples_comes_back_whole() {
        let pcm = tone(5, 0.3);
        let back = decode(&encode(&pcm), 5).unwrap();
        assert_eq!(back.len(), 10);
    }

    #[test]
    fn rubbish_is_not_a_block() {
        assert!(decode(&[1, 2], 2).is_none());
        assert!(decode(&[0, 0, 200, 0, 1], 2).is_none(), "step out of range");
        assert!(decode(&[0, 0, 0, 0, 1], 9).is_none(), "wrong length");
        assert!(encode(&[]).is_empty());
        assert!(encode(&vec![0u8; (MAX_SAMPLES + 1) * 2]).is_empty());
    }

    #[test]
    fn loudness_is_measured() {
        assert_eq!(level(&[0u8; 640]), 0.0);
        let loud = level(&tone(320, 0.9));
        let soft = level(&tone(320, 0.05));
        assert!(loud > 0.5 && soft < 0.05, "{loud} {soft}");
    }
}
