use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
pub struct Integ {
    pub nonce: String,
    pub mask: String,
    pub partial: String,
    pub ima_ml_entry: Option<String>,
}

/// Unified-Identity - Phase 3: Geolocation structure
/// type: "mobile" or "gnss"
/// sensor_id: Sensor identifier (e.g., USB device ID for mobile, device path for GNSS)
/// value: Optional for mobile, mandatory for gnss (GNSS coordinates, accuracy, etc.)
#[derive(Serialize, Deserialize, Debug, Clone, Default)]
pub struct Geolocation {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub r#type: Option<String>, // "mobile" or "gnss"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sensor_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>, // Optional for mobile, mandatory for gnss
}

#[derive(Serialize, Deserialize, Debug, Default)]
pub struct KeylimeQuote {
    pub quote: String, // 'r' + quote + sig + pcrblob
    pub hash_alg: String,
    pub enc_alg: String,
    pub sign_alg: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pubkey: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ima_measurement_list: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mb_measurement_list: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ima_measurement_list_entry: Option<u64>,
    // Unified-Identity - Phase 3: Geolocation sensor metadata
    #[serde(skip_serializing_if = "Option::is_none")]
    pub geolocation: Option<Geolocation>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_keylime_quote_serialization() {
        let quote = KeylimeQuote {
            quote: "example_quote".to_string(),
            hash_alg: "SHA256".to_string(),
            enc_alg: "AES".to_string(),
            sign_alg: "RSASSA-PSS".to_string(),
            pubkey: Some("example_pubkey".to_string()),
            ima_measurement_list: Some("example_ima_ml".to_string()),
            mb_measurement_list: None,
            ima_measurement_list_entry: Some(12345),
            geolocation: None,
        };

        let serialized = serde_json::to_string(&quote).unwrap(); //#[allow_ci]
        assert!(serialized.contains("example_quote"));
        assert!(serialized.contains("SHA256"));
        assert!(serialized.contains("AES"));
        assert!(serialized.contains("RSASSA-PSS"));
        assert!(serialized.contains("example_pubkey"));
        assert!(serialized.contains("example_ima_ml"));
        assert!(serialized.contains("12345"));

        let pretty_serialized = serde_json::to_string_pretty(&quote).unwrap(); //#[allow_ci]
        assert_eq!(
            pretty_serialized,
            r#"{
  "quote": "example_quote",
  "hash_alg": "SHA256",
  "enc_alg": "AES",
  "sign_alg": "RSASSA-PSS",
  "pubkey": "example_pubkey",
  "ima_measurement_list": "example_ima_ml",
  "ima_measurement_list_entry": 12345
}"#
        );
    }

    #[test]
    fn test_geolocation_serialization() {
        let geo = Geolocation {
            r#type: Some("mobile".to_string()),
            sensor_id: Some("12d1:1433".to_string()),
            value: None,
        };

        let serialized = serde_json::to_string(&geo).unwrap(); //#[allow_ci]
        assert!(serialized.contains("mobile"));
        assert!(serialized.contains("12d1:1433"));
        assert!(!serialized.contains("value")); // value should be omitted when None

        let geo_gnss = Geolocation {
            r#type: Some("gnss".to_string()),
            sensor_id: Some("/dev/gps0".to_string()),
            value: Some("N40.4168,W3.7038".to_string()),
        };

        let serialized_gnss = serde_json::to_string(&geo_gnss).unwrap(); //#[allow_ci]
        assert!(serialized_gnss.contains("gnss"));
        assert!(serialized_gnss.contains("/dev/gps0"));
        assert!(serialized_gnss.contains("N40.4168,W3.7038"));
    }
}
