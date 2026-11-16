use crate::sources::item;
use anyhow::{Context, Result, bail};
use chrono::{
    DateTime, Duration, FixedOffset, Local, Months, NaiveDate, NaiveDateTime, NaiveTime,
    SecondsFormat, TimeZone, Utc,
};
use regex::Regex;
use serde_json::{Value, json};
pub struct Dates {
    now: DateTime<FixedOffset>,
}
impl Default for Dates {
    fn default() -> Self {
        Self {
            now: Local::now().fixed_offset(),
        }
    }
}
impl Dates {
    fn row(&self, query: &str, value: &str, description: &str) -> Vec<Value> {
        let mut r = item("date", query, value, description);
        r["value"] = json!(value);
        vec![r]
    }
    pub fn parse(&self, text: &str) -> Result<DateTime<FixedOffset>> {
        let text = text.trim().trim_matches(['\'', '"']);
        let lower = text.to_lowercase();
        if lower == "now" {
            return Ok(self.now);
        }
        let date = self.now.date_naive();
        let midnight = |date: NaiveDate| -> Result<DateTime<FixedOffset>> {
            Local
                .from_local_datetime(&date.and_time(NaiveTime::MIN))
                .earliest()
                .map(|t| t.fixed_offset())
                .context("Local time does not exist")
        };
        if ["today", "tomorrow", "yesterday"].contains(&lower.as_str()) {
            return midnight(
                date + Duration::days(match lower.as_str() {
                    "tomorrow" => 1,
                    "yesterday" => -1,
                    _ => 0,
                }),
            );
        }
        for format in [
            "%+",
            "%Y-%m-%dT%H:%M%:z",
            "%Y-%m-%d %H:%M%:z",
            "%Y-%m-%d %H:%M %:z",
            "%Y-%m-%dT%H:%M:%S%:z",
        ] {
            if let Ok(t) = DateTime::parse_from_str(text, format) {
                return Ok(t);
            }
        }
        let zone = Regex::new(r"\s+([A-Za-z_]+/[A-Za-z_/]+)$")?.captures(text);
        let (text, zone) = if let Some(c) = zone {
            (
                &text[..c.get(0).unwrap().start()],
                Some(c[1].parse::<chrono_tz::Tz>()?),
            )
        } else {
            (text, None)
        };
        let mut parsed = None;
        for format in [
            "%Y-%m-%dT%H:%M:%S",
            "%Y-%m-%dT%H:%M",
            "%Y-%m-%d %H:%M:%S",
            "%Y-%m-%d %H:%M",
            "%d %B %Y %H:%M",
            "%d %b %Y %H:%M",
        ] {
            if let Ok(t) = NaiveDateTime::parse_from_str(text, format) {
                parsed = Some(t);
                break;
            }
        }
        if parsed.is_none() {
            for format in [
                "%Y-%m-%d",
                "%d %B %Y",
                "%d %b %Y",
                "%B %d %Y",
                "%b %d %Y",
                "%B %d, %Y",
                "%b %d, %Y",
                "%m/%d/%Y",
            ] {
                if let Ok(d) = NaiveDate::parse_from_str(text, format) {
                    parsed = Some(d.and_time(NaiveTime::MIN));
                    break;
                }
            }
        }
        if parsed.is_none() {
            let normalized = Regex::new(r"(?i)\s*(am|pm)$")?
                .replace(text, " $1")
                .to_uppercase();
            for format in ["%H:%M:%S", "%H:%M", "%H", "%I:%M %p", "%I %p"] {
                if let Ok(t) = NaiveTime::parse_from_str(&normalized, format) {
                    parsed = Some(date.and_time(t));
                    break;
                }
            }
        }
        let parsed =
            parsed.context("Use an ISO date, named calendar date, time, or IANA timezone")?;
        if let Some(zone) = zone {
            zone.from_local_datetime(&parsed)
                .earliest()
                .map(|t| t.fixed_offset())
                .context("This time does not exist in the selected timezone")
        } else {
            Local
                .from_local_datetime(&parsed)
                .earliest()
                .map(|t| t.fixed_offset())
                .context("Local time does not exist")
        }
    }
    pub fn search(&mut self, query: &str) -> Result<Vec<Value>> {
        self.now = Local::now().fixed_offset();
        self.search_at(query)
    }
    fn search_at(&self, query: &str) -> Result<Vec<Value>> {
        if let Some(c) =
            Regex::new(r"(?i)^(days|time|hours)\s+between\s+(.+?)\s+and\s+(.+)$")?.captures(query)
        {
            let a = self.parse(&c[2])?;
            let mut b = self.parse(&c[3])?;
            let clock = Regex::new(r"(?i)^\s*\d{1,2}(?::\d\d)?\s*(?:am|pm)?\s*$")?;
            if b < a && clock.is_match(&c[2]) && clock.is_match(&c[3]) {
                b += Duration::days(1);
            }
            if c[1].eq_ignore_ascii_case("days") {
                let days = (b.date_naive() - a.date_naive()).num_days();
                return Ok(self.row(
                    query,
                    &format!("{days} {}", if days.abs() == 1 { "day" } else { "days" }),
                    &format!(
                        "{} → {} · Calendar days, end date excluded",
                        a.date_naive(),
                        b.date_naive()
                    ),
                ));
            }
            let seconds = (b - a).num_seconds();
            let minutes = (seconds as f64 / 60.).round_ties_even().abs() as u64;
            return Ok(self.row(
                query,
                &format!(
                    "{}{} hours, {} minutes",
                    if seconds < 0 { "−" } else { "" },
                    minutes / 60,
                    minutes % 60
                ),
                &format!(
                    "{} → {} · {} hours",
                    a.format("%Y-%m-%d %H:%M%:z"),
                    b.format("%Y-%m-%d %H:%M%:z"),
                    seconds as f64 / 3600.
                ),
            ));
        }
        if let Some(c)=Regex::new(r"(?i)^(today|tomorrow|yesterday|\d{4}-\d\d-\d\d)\s*([+-])\s*(\d+)\s*(days?|weeks?|months?|years?)$")?.captures(query){let start=self.parse(&c[1])?;let amount=c[3].parse::<u32>()?;if amount>1_000_000{bail!("Date offset is too large");}let sign=if &c[2]=="+"{1}else{-1};let unit=c[4].to_lowercase();let date=if unit.starts_with("month")||unit.starts_with("year"){let months=Months::new(amount.checked_mul(if unit.starts_with("year"){12}else{1}).context("Date offset overflow")?);if sign>0{start.date_naive().checked_add_months(months)}else{start.date_naive().checked_sub_months(months)}}else{start.date_naive().checked_add_signed(Duration::days(i64::from(amount)*sign*if unit.starts_with("week"){7}else{1}))}.context("Date is out of range")?;return Ok(self.row(query,&date.format("%Y-%m-%d").to_string(),&date.format("%A, %d %B %Y").to_string()));}
        if let Some(c) = Regex::new(r"(?i)^(?:unix|timestamp)\s+(-?\d{1,13}|now)$")?.captures(query)
        {
            if c[1].eq_ignore_ascii_case("now") {
                return Ok(self.row(
                    query,
                    &self.now.timestamp().to_string(),
                    "Unix timestamp · seconds",
                ));
            }
            let n = c[1].parse::<i64>()?;
            let d = if c[1].trim_start_matches('-').len() == 13 {
                Utc.timestamp_millis_opt(n).single()
            } else {
                Utc.timestamp_opt(n, 0).single()
            }
            .context("Timestamp is out of range")?;
            return Ok(self.row(
                query,
                &d.to_rfc3339_opts(SecondsFormat::Secs, false),
                "UTC · Unix timestamp",
            ));
        }
        if let Some(c) = Regex::new(r"(?i)^(?:time|date)\s+(.+)$")?.captures(query) {
            let query_zone = c[1].replace(' ', "_").to_lowercase();
            if query_zone.starts_with("between") {
                return Ok(vec![]);
            }
            if query_zone == "local" {
                let mut rows = self.row(
                    &format!("{query}None"),
                    &self.now.format("%H:%M").to_string(),
                    &format!("Local time · {}", self.now.format("%A, %d %B %Y · %Z")),
                );
                rows[0]["value"] = json!(self.now.format("%Y-%m-%dT%H:%M%:z").to_string());
                return Ok(rows);
            }
            let mut result = vec![];
            let query_zone = if query_zone == "gmt" {
                "etc/gmt"
            } else {
                &query_zone
            };
            for zone in chrono_tz::TZ_VARIANTS
                .iter()
                .filter(|z| {
                    z.name().to_lowercase() == query_zone
                        || z.name().rsplit('/').next().unwrap().to_lowercase() == query_zone
                })
                .take(5)
            {
                let date = self.now.with_timezone(zone);
                let mut r = item(
                    "date",
                    &format!("{query}{}", zone.name()),
                    &date.format("%H:%M").to_string(),
                    &format!("{} · {}", zone.name(), date.format("%A, %d %B %Y · %Z")),
                );
                r["value"] = json!(date.format("%Y-%m-%dT%H:%M%:z").to_string());
                result.push(r);
            }
            return Ok(result);
        }
        if ["today", "tomorrow", "yesterday"].contains(&query.to_lowercase().as_str()) {
            let date = self.parse(query)?;
            return Ok(self.row(
                query,
                &date.format("%Y-%m-%d").to_string(),
                &date.format("%A, %d %B %Y").to_string(),
            ));
        }
        Ok(vec![])
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn calendar_and_offsets() {
        let d = Dates {
            now: DateTime::parse_from_rfc3339("2026-11-15T12:30:00+00:00").unwrap(),
        };
        for (q, v) in [
            ("days between 28 February 2024 and 1 March 2024", "2 days"),
            ("2024-01-31 + 1 month", "2024-02-29"),
            ("time between 23:00 and 01:00", "2 hours, 0 minutes"),
            (
                "time between 2026-03-29T01:00+01:00 and 2026-03-29T04:00+02:00",
                "2 hours, 0 minutes",
            ),
            ("timestamp now", "1794745800"),
        ] {
            assert_eq!(d.search_at(q).unwrap()[0]["value"], v, "{q}");
        }
        assert!(
            d.search_at("days between 2026-02-30 and 2026-03-01")
                .is_err()
        );
    }
}
