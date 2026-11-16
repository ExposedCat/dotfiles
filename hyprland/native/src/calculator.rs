use crate::{sources::item, util::*};
use anyhow::Result;
use regex::Regex;
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet},
    fs,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};
pub struct Calculator {
    command: Vec<String>,
    cache: PathBuf,
    currencies: HashSet<String>,
    names: HashMap<String, String>,
    money: Regex,
    scalar: Regex,
    token: Regex,
    functions: Option<HashSet<String>>,
    refreshing: Arc<AtomicBool>,
}
impl Calculator {
    pub fn new() -> Result<Self> {
        let cache = xdg("XDG_CACHE_HOME", ".cache").join("dotfiles/hyprland/qalculate");
        fs::create_dir_all(&cache)?;
        let portable = home().join(".local/lib/dotfiles/qalculate");
        let command = if exists("qalc") {
            vec!["qalc".into()]
        } else if portable.join("qalc").is_file() && exists("bwrap") {
            vec![
                "bwrap".into(),
                "--ro-bind".into(),
                "/".into(),
                "/".into(),
                "--tmpfs".into(),
                "/usr/share".into(),
                "--ro-bind".into(),
                portable.join("share").to_string_lossy().into(),
                "/usr/share/qalculate".into(),
                "--bind".into(),
                cache.to_string_lossy().into(),
                cache.to_string_lossy().into(),
                "--setenv".into(),
                "LD_LIBRARY_PATH".into(),
                portable.to_string_lossy().into(),
                "--".into(),
                portable.join("qalc").to_string_lossy().into(),
            ]
        } else {
            vec![]
        };
        let mut currencies = HashSet::new();
        let mut names = HashMap::new();
        for path in [
            PathBuf::from("/usr/share/qalculate/currencies.xml"),
            portable.join("share/currencies.xml"),
        ] {
            if let Ok(text) = fs::read_to_string(path) {
                for m in Regex::new(r"\b[A-Z]{3}\b")?.find_iter(&text) {
                    currencies.insert(m.as_str().to_string());
                }
                let doc = roxmltree::Document::parse(&text)?;
                for n in doc
                    .descendants()
                    .filter(|n| n.has_tag_name("names") && n.attributes().len() == 0)
                {
                    if let Some(text) = n.text() {
                        let aliases: Vec<_> = text
                            .split(',')
                            .map(|s| s.rsplit(':').next().unwrap())
                            .collect();
                        if let Some(code) = aliases.iter().find(|&&s| currencies.contains(s)) {
                            for alias in &aliases {
                                names.insert(alias.to_string(), code.to_string());
                            }
                        }
                    }
                }
                break;
            }
        }
        let mut aliases: Vec<_> = names.keys().cloned().collect();
        aliases.sort_by_key(|s| std::cmp::Reverse(s.len()));
        let aliases = if aliases.is_empty() {
            "(?!)".into()
        } else {
            aliases
                .iter()
                .map(|s| regex::escape(s))
                .collect::<Vec<_>>()
                .join("|")
        };
        let aliases = aliases.replace("(?!)", "__no_currency__");
        let number = r"[+−-]?\d+(?:\.\d+)?(?:E[+−-]?\d+)?";
        Ok(Self {
            command,
            cache,
            currencies,
            names,
            money: Regex::new(&format!(
                r"^(?:[+−-]?(?P<prefix>{aliases})\s*{number}|{number}\s*(?P<suffix>{aliases}))$"
            ))?,
            scalar: Regex::new(&format!(r"^{number}(?:\s*/\s*{number})?$"))?,
            token: Regex::new(&format!("(?i){aliases}"))?,
            functions: None,
            refreshing: Arc::new(AtomicBool::new(false)),
        })
    }
    pub fn available(&self) -> bool {
        !self.command.is_empty()
    }
    fn command(&self) -> std::process::Command {
        let mut c = std::process::Command::new(&self.command[0]);
        c.args(&self.command[1..])
            .env("LC_ALL", "C.UTF-8")
            .env("QALCULATE_USER_DIR", &self.cache);
        c
    }
    pub fn refresh(&self) {
        if !self.available() || self.refreshing.load(Ordering::Relaxed) {
            return;
        }
        let marker = self.cache.join("last-refresh");
        if marker
            .metadata()
            .ok()
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.elapsed().ok())
            .is_some_and(|d| d < Duration::from_secs(86400))
        {
            return;
        }
        if self.refreshing.swap(true, Ordering::Relaxed) {
            return;
        }
        let mut c = self.command();
        c.args(["-e", "-t", "-s", "save config no"]);
        let flag = self.refreshing.clone();
        std::thread::spawn(move || {
            if output(c, Some(vec![]), Duration::from_secs(12)).is_ok() {
                let _ = fs::write(marker, "");
            }
            flag.store(false, Ordering::Relaxed);
        });
    }
    pub fn evaluate(&self, expression: &str) -> Result<String> {
        if !self.available() {
            return Ok(String::new());
        }
        let mut c = self.command();
        c.args([
            "--defaults",
            "-t",
            "-m",
            "300",
            "-s",
            "save config no",
            "-s",
            "save definitions no",
            "-s",
            "update exchange rates 0",
            "-s",
            "max decimals 6",
            "-s",
            "show ending zeroes no",
            "--",
            expression,
        ]);
        let value = match output(c, None, Duration::from_millis(1200)) {
            Ok(s) => s.trim().to_string(),
            Err(_) => return Ok(String::new()),
        };
        if value.is_empty()
            || value.to_lowercase().contains("error:")
            || value.chars().count() > 240
            || value.contains('\n')
        {
            return Ok(String::new());
        }
        Ok(value)
    }
    fn rate_date(&self) -> String {
        let pattern = Regex::new(r#"time=['"]([0-9-]+)"#).unwrap();
        for root in [&self.cache, &PathBuf::from("/usr/share/qalculate")] {
            for file in ["eurofxref-daily.xml", "eurofxref-daily.xml.download"] {
                if let Ok(s) = fs::read_to_string(root.join(file))
                    && let Some(c) = pattern.captures(&s)
                {
                    return c[1].into();
                }
            }
        }
        "unknown".into()
    }
    pub fn infer(&self, expression: &str, value: &str) -> String {
        let terms: Vec<_> = Regex::new(r"\s+[+−-]\s+").unwrap().split(value).collect();
        if terms.len() < 2
            || !terms.iter().any(|s| self.money.is_match(s))
            || !terms.iter().any(|s| self.scalar.is_match(s))
            || !terms
                .iter()
                .all(|s| self.money.is_match(s) || self.scalar.is_match(s))
        {
            return expression.into();
        }
        let conversion = Regex::new(r"(?i)\s+(?:to|in)\s+[^()]+$|\s*(?:->|→)\s*[^()]+$")
            .unwrap()
            .find(expression);
        let (body, suffix) = conversion
            .map(|m| (&expression[..m.start()], &expression[m.start()..]))
            .unwrap_or((expression, ""));
        let (mut balance, mut missing) = (0, 0);
        for c in body.chars() {
            if c == '(' {
                balance += 1;
            } else if c == ')' {
                if balance > 0 {
                    balance -= 1;
                } else {
                    missing += 1;
                }
            }
        }
        let body = format!("{}{}{}", "(".repeat(missing), body, ")".repeat(balance));
        let codes: HashMap<_, _> = self
            .names
            .iter()
            .map(|(k, v)| (k.to_lowercase(), v.clone()))
            .collect();
        let currencies: Vec<_> = self
            .token
            .find_iter(&body)
            .filter(|m| {
                let boundary = |c: char| !c.is_alphabetic() && c != '_';
                body[..m.start()].chars().next_back().is_none_or(boundary)
                    && body[m.end()..].chars().next().is_none_or(boundary)
            })
            .filter_map(|m| {
                codes
                    .get(&m.as_str().to_lowercase())
                    .map(|c| (m.start(), m.end(), c.clone()))
            })
            .collect();
        if currencies.is_empty() {
            return expression.into();
        }
        let mut pairs = HashMap::new();
        let mut stack = vec![];
        for (i, c) in body.char_indices() {
            if c == '(' {
                stack.push(i);
            } else if c == ')'
                && let Some(open) = stack.pop()
            {
                pairs.insert(open, i);
            }
        }
        let numbers: Vec<_> = Regex::new(r"(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+−-]?\d+)?")
            .unwrap()
            .find_iter(&body)
            .map(|m| (m.start(), m.end()))
            .collect();
        fn walk(
            body: &str,
            start: usize,
            end: usize,
            pairs: &HashMap<usize, usize>,
            currencies: &[(usize, usize, String)],
            numbers: &[(usize, usize)],
        ) -> String {
            let segment = &body[start..end];
            let left = segment.len() - segment.trim_start().len();
            let start = start + left;
            let end = end - (segment.len() - segment.trim_end().len());
            if start >= end {
                return String::new();
            }
            if pairs.get(&start) == Some(&(end - 1)) {
                return format!(
                    "({})",
                    walk(body, start + 1, end - 1, pairs, currencies, numbers)
                );
            }
            let mut splits = vec![];
            let mut pos = start;
            while pos < end {
                if let Some(&close) = pairs.get(&pos) {
                    pos = close + 1;
                    continue;
                }
                let c = body[pos..].chars().next().unwrap();
                let previous = body[start..pos].trim_end().chars().next_back();
                if "+−-".contains(c)
                    && previous.is_some_and(|c| !"+−-*/^,;(<>=".contains(c))
                    && !numbers.iter().any(|&(a, b)| a < pos && pos < b)
                {
                    splits.push((pos, c.len_utf8()));
                }
                pos += c.len_utf8();
            }
            if !splits.is_empty() {
                let mut result = String::new();
                let mut left = start;
                for (index, &(right, len)) in
                    splits.iter().chain(std::iter::once(&(end, 0))).enumerate()
                {
                    let has = currencies.iter().any(|(a, _, _)| left <= *a && *a < right);
                    let any = currencies.iter().any(|(a, _, _)| start <= *a && *a < end);
                    let part = if has || !any || body[left..right].contains(['%', '‰', '‱']) {
                        walk(body, left, right, pairs, currencies, numbers)
                    } else {
                        let mut scopes: Vec<_> = pairs
                            .iter()
                            .filter(|&(a, b)| *a < left && right <= *b)
                            .map(|(&a, &b)| (a + 1, b))
                            .collect();
                        scopes.sort_by_key(|&(a, b)| b - a);
                        scopes.push((0, body.len()));
                        let code = scopes.into_iter().find_map(|(a, b)| {
                            let local: Vec<_> = currencies
                                .iter()
                                .filter(|(c, d, _)| a <= *c && *d <= b)
                                .collect();
                            local
                                .iter()
                                .rev()
                                .find(|(_, d, _)| *d <= left)
                                .or_else(|| local.iter().find(|(c, _, _)| *c >= right))
                                .map(|(_, _, c)| c.clone())
                        });
                        format!(
                            "({}) {}",
                            body[left..right].trim(),
                            code.unwrap_or_default()
                        )
                    };
                    result.push_str(&part);
                    if index < splits.len() {
                        result.push(' ');
                        result.push_str(&body[right..right + len]);
                        result.push(' ');
                    }
                    left = right + len;
                }
                return result;
            }
            let mut result = String::new();
            let mut pos = start;
            while pos < end {
                if let Some(&close) = pairs.get(&pos) {
                    result.push('(');
                    result.push_str(&walk(body, pos + 1, close, pairs, currencies, numbers));
                    result.push(')');
                    pos = close + 1;
                } else {
                    let c = body[pos..].chars().next().unwrap();
                    result.push(c);
                    pos += c.len_utf8();
                }
            }
            result
        }
        format!(
            "{}{suffix}",
            walk(&body, 0, body.len(), &pairs, &currencies, &numbers)
        )
    }
    pub fn search(&mut self, query: &str) -> Result<Vec<Value>> {
        if let Some(c) = Regex::new(
            r"(?i)^([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*([a-z]{3})(?:\s+(?:to\s+)?([a-z]{3}))?$",
        )?
        .captures(query)
        {
            let amount = &c[1];
            let source = c[2].to_uppercase();
            let targets: Vec<String> = if let Some(t) = c.get(3) {
                vec![t.as_str().to_uppercase()]
            } else {
                ["CZK", "USD", "EUR"]
                    .into_iter()
                    .filter(|c| *c != source)
                    .map(String::from)
                    .collect()
            };
            if !self.currencies.contains(&source)
                || targets.iter().any(|t| !self.currencies.contains(t))
            {
                return Ok(vec![]);
            }
            let mut result = vec![];
            for target in targets {
                let expression = format!("{amount} {source} to {target}");
                let value = self.evaluate(&expression)?;
                if !value.is_empty()
                    && !["unknown", "aborted", "undefined"]
                        .iter()
                        .any(|s| value.contains(s))
                {
                    let date = self.rate_date();
                    let mut r = item(
                        "currency",
                        &expression,
                        &value,
                        &format!("{amount} {source} → {target} · Rates {date}"),
                    );
                    r["value"] = json!(value);
                    r["rateDate"] = json!(date);
                    result.push(r);
                }
            }
            return Ok(result);
        }
        let mut expression = query.strip_prefix('=').unwrap_or(query).trim().to_string();
        if expression.is_empty() || Regex::new(r"[+*/^,−-]\s*$")?.is_match(&expression) {
            return Ok(vec![]);
        }
        let function = Regex::new(r"^([\w√]+)\s*\(")?
            .captures(&expression)
            .map(|c| c[1].to_string());
        if function.is_some() && self.functions.is_none() && self.available() {
            let mut c = self.command();
            c.arg("--list-functions");
            let text = output(c, None, Duration::from_millis(1200)).unwrap_or_default();
            self.functions = Some(
                Regex::new(r"[\w√]+")?
                    .find_iter(text.split("\n\n").next().unwrap_or(""))
                    .map(|m| m.as_str().to_string())
                    .collect(),
            );
        }
        let likely = Regex::new(r"^[+−-]?(?:\d|\.\d|\()")?.is_match(&expression)
            || function
                .as_ref()
                .is_some_and(|f| self.functions.as_ref().is_some_and(|fs| fs.contains(f)))
            || Regex::new(r"^(?:pi|π|e|tau)\s*[-+*/^]")?.is_match(&expression);
        if !query.starts_with('=')
            && (!likely || Regex::new(r"^[+−-]?\d+(?:\.\d+)?$")?.is_match(&expression))
        {
            return Ok(vec![]);
        }
        expression = Regex::new(r"(?i)\b([a-z]{3})\s+([a-z]{3})$")?
            .replace(&expression, |c: &regex::Captures| {
                if self.currencies.contains(&c[1].to_uppercase())
                    && self.currencies.contains(&c[2].to_uppercase())
                {
                    format!("{} to {}", &c[1], &c[2])
                } else {
                    c[0].into()
                }
            })
            .into();
        expression = Regex::new(r"(?i)\bin\s+([a-z]{3})$")?
            .replace(&expression, |c: &regex::Captures| {
                if self.currencies.contains(&c[1].to_uppercase()) {
                    format!("to {}", &c[1])
                } else {
                    c[0].into()
                }
            })
            .into();
        let mut value = self.evaluate(&expression)?;
        if value.is_empty() {
            return Ok(vec![]);
        }
        let inferred = self.infer(&expression, &value);
        if inferred != expression {
            expression = inferred;
            value = self.evaluate(&expression)?;
            if value.is_empty() {
                return Ok(vec![]);
            }
        }
        let monetary = self.money.captures(&value);
        let currency = monetary
            .as_ref()
            .and_then(|c| c.name("prefix").or_else(|| c.name("suffix")))
            .and_then(|m| self.names.get(m.as_str()))
            .cloned();
        let make = |text: &str, value: &str| {
            let mut r = item(
                if currency.is_some() {
                    "currency"
                } else {
                    "calculation"
                },
                text,
                value,
                text,
            );
            r["value"] = json!(value);
            if currency.is_some() {
                r["rateDate"] = json!(self.rate_date());
            }
            r
        };
        let mut results = vec![make(query, &value)];
        if let Some(source) = &currency
            && !Regex::new(r"(?i)\s+(?:to|in)\s+|->|→")?.is_match(&expression)
        {
            for target in ["CZK", "USD", "EUR"] {
                if target == source {
                    continue;
                }
                let conversion = format!("{expression} to {target}");
                let converted = self.evaluate(&conversion)?;
                if !converted.is_empty() && converted != value {
                    results.push(make(&conversion, &converted));
                }
            }
        }
        Ok(results)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn migration_regression_vectors() {
        let mut calculator = Calculator::new().unwrap();
        if !calculator.available() {
            return;
        }
        let data: Value =
            serde_json::from_str(include_str!("../tests/fixtures/calculator.json")).unwrap();
        for row in rows(&data["values"]) {
            let query = row[0].as_str().unwrap();
            assert_eq!(
                calculator.search(query).unwrap()[0]["value"],
                row[1],
                "{query}"
            );
        }
        for row in rows(&data["equivalent"]) {
            let query = row[0].as_str().unwrap();
            let expected = calculator.evaluate(row[1].as_str().unwrap()).unwrap();
            assert_eq!(
                calculator.search(query).unwrap()[0]["value"],
                expected,
                "{query}"
            );
        }
    }
    #[test]
    fn math_and_currency_contract() {
        let mut c = Calculator::new().unwrap();
        if !c.available() {
            return;
        }
        for (q, value) in [
            ("sqrt(81)", "9"),
            ("2 + 2) * 3", "12"),
            ("2 * (3 + 4", "14"),
        ] {
            assert_eq!(c.search(q).unwrap()[0]["value"], value, "{q}");
        }
        for (q, explicit) in [
            ("12 eur + (5 + 12 czk)", "12 eur + 17 czk"),
            ("2 + 15 eur) * 3", "51 eur"),
            ("1e-3 + 15 eur", "15.001 eur"),
            ("2 + 15 eur + 10%", "18.7 eur"),
        ] {
            assert_eq!(
                c.search(q).unwrap()[0]["value"],
                c.evaluate(explicit).unwrap(),
                "{q}"
            );
        }
        assert_eq!(
            c.search("100 usd eur").unwrap()[0]["id"],
            "currency:100 USD to EUR"
        );
        assert!(c.search("foo(2)").unwrap().is_empty());
    }
}
