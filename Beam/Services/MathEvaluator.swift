import Foundation
import SwiftUI

struct MathEvaluator {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 10
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()

    static func evaluate(_ input: String) -> (expression: String, result: String, isInfo: Bool)? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Try currency-aware math first (e.g. "$6 $7 $8.9", "$1 + 1eur", "add $5 $10")
        if let r = evaluateCurrencyMath(trimmed) { return (r.expression, r.result, false) }

        // Try natural language math first
        if let r = evaluateNaturalLanguage(trimmed) { return (r.expression, r.result, false) }

        // Try date calculations
        if let r = evaluateDate(trimmed) { return (r.expression, r.result, true) }

        // Dimensional list (e.g. "3mm x 4mm x 6mm to in", "3 x 4 x 6 mm")
        if let r = evaluateDimensions(trimmed) { return (r.expression, r.result, false) }

        // Try unit conversions
        if let r = evaluateUnitConversion(trimmed) { return (r.expression, r.result, false) }

        // Try currency conversions (explicit "X to Y")
        if let r = evaluateCurrency(trimmed) { return (r.expression, r.result, false) }

        // Auto-convert standalone currency to USD (e.g. "1 rmb" -> "$0.14")
        if let r = evaluateAutoCurrencyConvert(trimmed) { return (r.expression, r.result, false) }

        // Auto-convert standalone units to US standard
        if let r = evaluateAutoUnitConvert(trimmed) { return (r.expression, r.result, false) }

        // UPC/GTIN check digit (e.g. 11-digit -> UPC-A, 13-digit -> GTIN-14)
        if let r = evaluateCheckDigit(trimmed) { return (r.expression, r.result, true) }

        // Try standalone number abbreviation (e.g. "5k" -> "5,000", "2.5 million" -> "2,500,000")
        if let r = evaluateAbbreviation(trimmed) { return (r.expression, r.result, false) }

        // Equation solving (e.g. "21^2*x^2=16.25^2")
        if let r = evaluateEquation(trimmed) { return (r.expression, r.result, true) }

        // Standard math expression
        if let r = evaluateExpression(trimmed) { return (r.expression, r.result, false) }

        return nil
    }

    // MARK: - Currency-Aware Math

    // Symbols/prefixes that denote currencies
    private static let currencySymbols: [String: String] = [
        "$": "usd", "usd": "usd",
        "€": "eur", "eur": "eur",
        "£": "gbp", "gbp": "gbp",
        "¥": "jpy", "jpy": "jpy",
        "₪": "ils", "ils": "ils", "nis": "ils",
        "cad": "cad", "aud": "aud", "chf": "chf",
        "cny": "cny", "rmb": "cny", "inr": "inr", "mxn": "mxn",
        "brl": "brl", "krw": "krw", "sek": "sek",
        "nok": "nok", "dkk": "dkk", "sgd": "sgd",
        "hkd": "hkd", "nzd": "nzd", "aed": "aed",
        "zar": "zar", "try": "try", "thb": "thb",
        "pln": "pln", "php": "php", "idr": "idr",
        "twd": "twd", "czk": "czk",
    ]

    private static let currencySymbolToFormat: [String: (String, String)] = [
        "usd": ("$", ""), "eur": ("€", ""), "gbp": ("£", ""),
        "jpy": ("¥", ""), "ils": ("₪", ""), "cad": ("CA$", ""),
        "aud": ("A$", ""), "chf": ("", " CHF"), "cny": ("¥", ""),
    ]

    /// Handles: "$6 7 8.9 6", "add $5 10 20", "$1 + 1eur", "$100 + €50 + £30"
    /// If even ONE token has a currency, bare numbers inherit that currency.
    private static func evaluateCurrencyMath(_ input: String) -> (expression: String, result: String)? {
        // Drop "~" (approximately) so it doesn't hide an "x"-multiplication (e.g. "18 x ~$5").
        let trimmed = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "~", with: "")

        // If the expression has parentheses, multiplication, division, or power — it's a math expression, not a currency sum.
        // "x"/"×" followed by a number or currency (e.g. "18 x $5", "18 x $.70") is multiplication too.
        if trimmed.contains("(") || trimmed.contains(")") || trimmed.contains("*") ||
           trimmed.contains("/") || trimmed.contains("^") ||
           trimmed.range(of: #"[xX×]\s*[\d$€£¥₪.]"#, options: .regularExpression) != nil {
            return nil
        }

        // Check if input contains currency symbols BEFORE numbers (not after, e.g. "10$" is not currency)
        let symbolBeforeNum = #"[\$€£¥₪]\s*\d"#
        let numBeforeCode = #"\d\s*(usd|eur|gbp|jpy|cad|aud|chf|cny|rmb|ils|nis|inr|mxn|brl|krw|sek|nok|dkk|sgd|hkd|nzd|aed|zar|thb|pln)\b"#
        let codeAlone = #"\b(usd|eur|gbp|jpy|cad|aud|chf|cny|rmb|ils|nis|inr|mxn|brl|krw|sek|nok|dkk|sgd|hkd|nzd|aed|zar|thb|pln)\s*\d"#
        let hasCurrencySymbol = trimmed.range(of: symbolBeforeNum, options: .regularExpression) != nil
        let hasCurrencyCode = trimmed.range(of: numBeforeCode, options: [.regularExpression, .caseInsensitive]) != nil
        let hasCurrencyPrefix = trimmed.range(of: codeAlone, options: [.regularExpression, .caseInsensitive]) != nil
        guard hasCurrencySymbol || hasCurrencyCode || hasCurrencyPrefix else { return nil }

        // Strip leading keyword if present
        let lower = trimmed.lowercased()
        let keywords = ["sum", "add", "total", "plus"]
        var working = trimmed
        for kw in keywords {
            if lower.hasPrefix(kw + " ") {
                working = String(trimmed.dropFirst(kw.count + 1)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Split into tokens by + or whitespace.
        // Convert subtraction "X-Y" into a signed-add "X -Y" so the regex tokenizer
        // can carry the negative sign through (otherwise "55760-$40560" sums to 96320).
        let cleanInput = working
            .replacingOccurrences(
                of: #"([\d\)])\s*-\s*([\$€£¥₪]|\d)"#,
                with: "$1 -$2",
                options: .regularExpression
            )
            .replacingOccurrences(of: "+", with: " ")

        // First pass: find what currency is present (to use as default for bare numbers)
        var detectedCurrency: String?
        let symScan = try! NSRegularExpression(pattern: #"[\$€£¥₪]"#)
        let codeScan = try! NSRegularExpression(pattern: #"\b(usd|eur|gbp|jpy|cad|aud|chf|cny|rmb|ils|nis|inr|mxn|brl|krw|sek|nok|dkk|sgd|hkd|nzd|aed|zar|thb|pln)\b"#, options: .caseInsensitive)
        let fullRange = NSRange(cleanInput.startIndex..., in: cleanInput)
        if let symMatch = symScan.firstMatch(in: cleanInput, range: fullRange),
           let r = Range(symMatch.range, in: cleanInput) {
            detectedCurrency = currencySymbols[String(cleanInput[r])]
        } else if let codeMatch = codeScan.firstMatch(in: cleanInput, range: fullRange),
                  let r = Range(codeMatch.range(at: 1), in: cleanInput) {
            detectedCurrency = currencySymbols[String(cleanInput[r]).lowercased()]
        }
        guard let defaultCurrency = detectedCurrency else { return nil }

        // Second pass: parse all tokens (currency-tagged and bare numbers).
        // Optional leading "-" denotes subtraction; carried through to the amount sign.
        let tokenPattern = #"(-?)\s*([\$€£¥₪])\s*([\d,.]+)|(-?)\s*([\d,.]+)\s*([a-zA-Z₪€£¥\$]{2,3})|(-?)\s*([\d,.]+)"#
        let regex = try! NSRegularExpression(pattern: tokenPattern, options: .caseInsensitive)
        let cleanNoComma = cleanInput.replacingOccurrences(of: ",", with: "")
        let nsRange = NSRange(cleanNoComma.startIndex..., in: cleanNoComma)
        let matches = regex.matches(in: cleanNoComma, range: nsRange)

        guard matches.count >= 2 else { return nil }

        struct CurrencyAmount {
            let amount: Double
            let currency: String
        }

        var amounts: [CurrencyAmount] = []
        var firstCurrency: String?

        func signedAmount(_ signRange: NSRange, _ value: Double) -> Double {
            if signRange.location != NSNotFound,
               let r = Range(signRange, in: cleanNoComma),
               String(cleanNoComma[r]) == "-" { return -value }
            return value
        }

        for match in matches {
            var amount: Double?
            var currency: String?

            // Pattern 1: [-]symbol+number (e.g. "$5", "-$40")
            if match.range(at: 2).location != NSNotFound,
               let symRange = Range(match.range(at: 2), in: cleanNoComma),
               let numRange = Range(match.range(at: 3), in: cleanNoComma) {
                let sym = String(cleanNoComma[symRange])
                let num = String(cleanNoComma[numRange])
                currency = currencySymbols[sym]
                amount = parseNumber(num).map { signedAmount(match.range(at: 1), $0) }
            }
            // Pattern 2: [-]number+code (e.g. "5eur", "-5eur")
            else if match.range(at: 5).location != NSNotFound,
                    let numRange = Range(match.range(at: 5), in: cleanNoComma),
                    let codeRange = Range(match.range(at: 6), in: cleanNoComma) {
                let num = String(cleanNoComma[numRange])
                let code = String(cleanNoComma[codeRange]).lowercased()
                currency = currencySymbols[code]
                amount = parseNumber(num).map { signedAmount(match.range(at: 4), $0) }
            }
            // Pattern 3: [-]bare number — inherit the detected currency
            else if match.range(at: 8).location != NSNotFound,
                    let numRange = Range(match.range(at: 8), in: cleanNoComma) {
                let num = String(cleanNoComma[numRange])
                amount = parseNumber(num).map { signedAmount(match.range(at: 7), $0) }
                currency = defaultCurrency
            }

            if let amt = amount, let cur = currency {
                if firstCurrency == nil { firstCurrency = cur }
                amounts.append(CurrencyAmount(amount: amt, currency: cur))
            }
        }

        guard amounts.count >= 2, let targetCurrency = firstCurrency else { return nil }

        // Convert all amounts to the first currency and sum
        let rates = getCachedRates()
        var total: Double = 0
        var needsConversion = false

        for ca in amounts {
            if ca.currency == targetCurrency {
                total += ca.amount
            } else {
                needsConversion = true
                if let rates = rates,
                   let fromRate = rates[ca.currency],
                   let toRate = rates[targetCurrency] {
                    total += ca.amount / fromRate * toRate
                } else {
                    fetchRates()
                    return (expression: input, result: "Loading rates...")
                }
            }
        }

        // Format result with currency symbol
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 2
        fmt.minimumFractionDigits = 2
        fmt.usesGroupingSeparator = true
        let formatted = fmt.string(from: NSNumber(value: total)) ?? String(format: "%.2f", total)

        let (prefix, suffix) = currencySymbolToFormat[targetCurrency] ?? ("", " \(targetCurrency.uppercased())")
        let resultStr = needsConversion ? "~\(prefix)\(formatted)\(suffix)" : "\(prefix)\(formatted)\(suffix)"

        return (expression: input, result: resultStr)
    }

    // MARK: - Natural Language Math

    private static func evaluateNaturalLanguage(_ input: String) -> (expression: String, result: String)? {
        let lower = input.lowercased()
        // Split on newlines too, so pasted columns work (e.g. "sum\n4\n1.5\n2").
        let parts = lower.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }

        let keyword = parts[0]
        // Strip currency symbols, parentheses, and commas before parsing numbers
        // (so "avg (22.00 $25.75)" parses 22 and 25.75).
        func cleanNumberTokens(_ tokens: [String]) -> [Double] {
            tokens
                .map { $0.replacingOccurrences(of: #"[\$€£¥₪(),]"#, with: "", options: .regularExpression) }
                .compactMap { parseNumber($0) }
        }
        let numbers = cleanNumberTokens(Array(parts.dropFirst()))
        guard !numbers.isEmpty else { return nil }

        var result: Double?
        var label: String?

        switch keyword {
        case "sum", "add", "total", "plus":
            result = numbers.reduce(0, +)
            label = "Sum"
        case "average", "avg", "mean":
            result = numbers.reduce(0, +) / Double(numbers.count)
            label = "Average"
        case "multiply", "product":
            result = numbers.reduce(1, *)
            label = "Product"
        case "subtract", "minus", "difference":
            if numbers.count >= 2 {
                result = numbers.dropFirst().reduce(numbers[0], -)
            }
            label = "Difference"
        case "divide":
            if numbers.count == 2, numbers[1] != 0 {
                result = numbers[0] / numbers[1]
            }
            label = "Division"
        case "max", "maximum", "largest":
            result = numbers.max()
            label = "Max"
        case "min", "minimum", "smallest":
            result = numbers.min()
            label = "Min"
        case "median":
            let sorted = numbers.sorted()
            let count = sorted.count
            if count % 2 == 0 {
                result = (sorted[count/2 - 1] + sorted[count/2]) / 2.0
            } else {
                result = sorted[count/2]
            }
            label = "Median"
        case "percent", "percentage":
            // "percent 15 of 200" or "percent 15 200"
            let filtered = parts.dropFirst().filter { $0 != "of" }
            let nums = cleanNumberTokens(Array(filtered))
            if nums.count == 2 {
                result = nums[0] / 100.0 * nums[1]
                label = "\(format(nums[0]))% of \(format(nums[1]))"
            }
        default:
            return nil
        }

        guard let val = result else { return nil }
        return (expression: label ?? keyword.capitalized, result: format(val))
    }

    // MARK: - Date Calculations

    private static func evaluateDate(_ input: String) -> (expression: String, result: String)? {
        let lower = input.lowercased().trimmingCharacters(in: .whitespaces)

        // "<date> + X unit [+/- Y unit ...]" — chained date arithmetic
        // e.g. "9/1 + 85 days", "today + 10 years + 364 days", "sep 1 + 1 month - 5 days"
        // Single op with no date prefix (e.g. "+ 85 days") falls through to the relative-to-today block below.
        let trimmedInput = input.trimmingCharacters(in: .whitespaces)
        let opPattern = #"([+\-])\s*(\d+\.?\d*)\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?|yrs?)"#
        if let regex = try? NSRegularExpression(pattern: opPattern, options: [.caseInsensitive]) {
            let nsInput = trimmedInput as NSString
            let opMatches = regex.matches(in: trimmedInput, range: NSRange(location: 0, length: nsInput.length))
            if !opMatches.isEmpty {
                let lastEnd = opMatches.last!.range.location + opMatches.last!.range.length
                let trailing = nsInput.substring(from: lastEnd).trimmingCharacters(in: .whitespaces)
                var contiguous = trailing.isEmpty
                for i in 1..<opMatches.count where contiguous {
                    let prevEnd = opMatches[i-1].range.location + opMatches[i-1].range.length
                    let between = nsInput.substring(with: NSRange(location: prevEnd, length: opMatches[i].range.location - prevEnd))
                    if !between.trimmingCharacters(in: .whitespaces).isEmpty { contiguous = false }
                }
                let baseStr = nsInput.substring(to: opMatches[0].range.location).trimmingCharacters(in: .whitespaces)
                if contiguous && (opMatches.count > 1 || !baseStr.isEmpty) {
                    let baseDate: Date? = baseStr.isEmpty ? Date() : parseDate(baseStr)
                    if let baseDate {
                        var current = baseDate
                        var showTime = false
                        let calendar = Calendar.current
                        var failed = false
                        for m in opMatches {
                            let matched = nsInput.substring(with: m.range).trimmingCharacters(in: .whitespaces)
                            let isNeg = matched.hasPrefix("-")
                            let afterSign = String(matched.dropFirst()).trimmingCharacters(in: .whitespaces)
                            let parts = afterSign.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                            guard parts.count >= 2, let amount = Double(parts[0]) else { failed = true; break }
                            let unit = parts.dropFirst().joined(separator: " ").lowercased()
                            let value = Int(amount) * (isNeg ? -1 : 1)
                            var stepped: Date?
                            if unit.hasPrefix("sec") { stepped = calendar.date(byAdding: .second, value: value, to: current); showTime = true }
                            else if unit.hasPrefix("min") { stepped = calendar.date(byAdding: .minute, value: value, to: current); showTime = true }
                            else if unit.hasPrefix("hour") || unit.hasPrefix("hr") { stepped = calendar.date(byAdding: .hour, value: value, to: current); showTime = true }
                            else if unit.hasPrefix("day") { stepped = calendar.date(byAdding: .day, value: value, to: current) }
                            else if unit.hasPrefix("week") { stepped = calendar.date(byAdding: .weekOfYear, value: value, to: current) }
                            else if unit.hasPrefix("month") { stepped = calendar.date(byAdding: .month, value: value, to: current) }
                            else if unit.hasPrefix("year") || unit.hasPrefix("yr") { stepped = calendar.date(byAdding: .year, value: value, to: current) }
                            guard let s = stepped else { failed = true; break }
                            current = s
                        }
                        if !failed {
                            let fmt = DateFormatter()
                            fmt.dateStyle = .long
                            fmt.timeStyle = showTime ? .short : .none
                            return (expression: input, result: fmt.string(from: current))
                        }
                    }
                }
            }
        }

        // "+ X days/hours/minutes/months/years" or "- X days/hours/minutes/months/years"
        if let _ = lower.range(of: #"^[+\-]\s*(\d+\.?\d*)\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?|yrs?)$"#, options: .regularExpression) {
            let isNegative = lower.hasPrefix("-")
            let stripped = lower.dropFirst().trimmingCharacters(in: .whitespaces)
            let numParts = stripped.components(separatedBy: .whitespaces)
            guard numParts.count >= 2, let amount = Double(numParts[0]) else { return nil }
            let unit = numParts.dropFirst().joined(separator: " ")
            let direction: Double = isNegative ? -1 : 1

            let calendar = Calendar.current
            var resultDate: Date?
            var showTime = false

            if unit.hasPrefix("sec") {
                resultDate = calendar.date(byAdding: .second, value: Int(amount * direction), to: Date())
                showTime = true
            } else if unit.hasPrefix("min") {
                resultDate = calendar.date(byAdding: .minute, value: Int(amount * direction), to: Date())
                showTime = true
            } else if unit.hasPrefix("hour") || unit.hasPrefix("hr") {
                resultDate = calendar.date(byAdding: .hour, value: Int(amount * direction), to: Date())
                showTime = true
            } else if unit.hasPrefix("day") {
                resultDate = calendar.date(byAdding: .day, value: Int(amount * direction), to: Date())
            } else if unit.hasPrefix("week") {
                resultDate = calendar.date(byAdding: .weekOfYear, value: Int(amount * direction), to: Date())
            } else if unit.hasPrefix("month") {
                resultDate = calendar.date(byAdding: .month, value: Int(amount * direction), to: Date())
            } else if unit.hasPrefix("year") || unit.hasPrefix("yr") {
                resultDate = calendar.date(byAdding: .year, value: Int(amount * direction), to: Date())
            }

            if let date = resultDate {
                let calendar = Calendar.current
                let now = Date()
                if showTime {
                    let timeFmt = DateFormatter()
                    timeFmt.dateStyle = .none
                    timeFmt.timeStyle = .short
                    var timeStr = timeFmt.string(from: date)

                    // Check if result crosses into a different day
                    let nowDay = calendar.startOfDay(for: now)
                    let resultDay = calendar.startOfDay(for: date)
                    let dayDiff = calendar.dateComponents([.day], from: nowDay, to: resultDay).day ?? 0
                    if dayDiff == 1 {
                        timeStr += " (tomorrow)"
                    } else if dayDiff == -1 {
                        timeStr += " (yesterday)"
                    } else if dayDiff != 0 {
                        let dateFmt = DateFormatter()
                        dateFmt.dateFormat = "MMM d"
                        timeStr += " (\(dateFmt.string(from: date)))"
                    }
                    return (expression: input, result: timeStr)
                } else {
                    let fmt = DateFormatter()
                    fmt.dateStyle = .long
                    fmt.timeStyle = .none
                    return (expression: input, result: fmt.string(from: date))
                }
            }
        }

        // "X days/weeks/months from now" or "X days/weeks/months ago"
        if let match = lower.range(of: #"^(\d+)\s+(days?|weeks?|months?|years?)\s+(from now|from today|ago)$"#, options: .regularExpression) {
            let matched = String(lower[match])
            let parts = matched.components(separatedBy: .whitespaces)
            guard let amount = Int(parts[0]) else { return nil }
            let unit = parts[1]
            let direction = matched.contains("ago") ? -1 : 1

            let calendar = Calendar.current
            var component: Calendar.Component = .day
            if unit.hasPrefix("week") { component = .weekOfYear }
            else if unit.hasPrefix("month") { component = .month }
            else if unit.hasPrefix("year") { component = .year }

            if let date = calendar.date(byAdding: component, value: amount * direction, to: Date()) {
                let fmt = DateFormatter()
                fmt.dateStyle = .long
                fmt.timeStyle = .none
                return (expression: input, result: fmt.string(from: date))
            }
        }

        // "days until <date>" or "days since <date>"
        if lower.hasPrefix("days until ") || lower.hasPrefix("days since ") || lower.hasPrefix("days to ") {
            let isSince = lower.hasPrefix("days since ")
            let prefix = lower.hasPrefix("days until ") ? "days until " :
                         lower.hasPrefix("days since ") ? "days since " : "days to "
            let dateStr = String(lower.dropFirst(prefix.count))
            if let target = parseDate(dateStr) {
                let calendar = Calendar.current
                let now = calendar.startOfDay(for: Date())
                let targetDay = calendar.startOfDay(for: target)
                let days = calendar.dateComponents([.day], from: now, to: targetDay).day ?? 0
                let absDays = abs(days)
                if isSince {
                    return (expression: input, result: "\(absDays) days")
                } else {
                    return (expression: input, result: "\(days) days")
                }
            }
        }

        // "days from <date> to <date>" or "days between <date> and <date>"
        if lower.hasPrefix("days from ") || lower.hasPrefix("days between ") {
            let prefix = lower.hasPrefix("days from ") ? "days from " : "days between "
            let rest = String(lower.dropFirst(prefix.count))
            let separator = lower.hasPrefix("days from ") ? " to " : " and "
            let dateParts = rest.components(separatedBy: separator)
            if dateParts.count == 2,
               let d1 = parseDate(dateParts[0].trimmingCharacters(in: .whitespaces)),
               let d2 = parseDate(dateParts[1].trimmingCharacters(in: .whitespaces)) {
                let calendar = Calendar.current
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: d1), to: calendar.startOfDay(for: d2)).day ?? 0
                return (expression: input, result: "\(abs(days)) days")
            }
        }

        // "today", "now", "what day is it"
        if lower == "today" || lower == "now" || lower == "date" || lower == "what day is it" {
            let fmt = DateFormatter()
            fmt.dateStyle = .full
            fmt.timeStyle = .none
            return (expression: "Today", result: fmt.string(from: Date()))
        }

        // "time"
        if lower == "time" || lower == "what time is it" {
            let fmt = DateFormatter()
            fmt.dateStyle = .none
            fmt.timeStyle = .short
            return (expression: "Time", result: fmt.string(from: Date()))
        }

        return nil
    }

    private static func parseDate(_ str: String) -> Date? {
        let lower = str.lowercased().trimmingCharacters(in: .whitespaces)

        // Named dates
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())

        let namedDates: [String: (Int, Int)] = [
            "christmas": (12, 25),
            "christmas eve": (12, 24),
            "new years": (1, 1),
            "new year": (1, 1),
            "new years eve": (12, 31),
            "valentines": (2, 14),
            "valentines day": (2, 14),
            "halloween": (10, 31),
            "july 4th": (7, 4),
            "independence day": (7, 4),
        ]

        if let (month, day) = namedDates[lower] {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            if let date = calendar.date(from: comps) {
                // If date already passed this year, use next year
                if date < Date() {
                    comps.year = year + 1
                }
                return calendar.date(from: comps)
            }
        }

        // "today" / "now"
        if lower == "today" || lower == "now" { return Date() }

        // Try common date formats
        let formats = [
            "MMMM d, yyyy", "MMMM d yyyy", "MMM d, yyyy", "MMM d yyyy",
            "MMMM d", "MMM d", "M/d/yyyy", "M/d/yy", "M/d",
            "yyyy-MM-dd", "MM-dd-yyyy", "d MMMM yyyy", "d MMMM", "d MMM"
        ]
        for format in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US")
            df.dateFormat = format
            if let date = df.date(from: str) {
                // If no year in format, set current year
                if !format.contains("y") {
                    var comps = calendar.dateComponents([.month, .day], from: date)
                    comps.year = year
                    if let d = calendar.date(from: comps), d < Date() {
                        comps.year = year + 1
                    }
                    return calendar.date(from: comps)
                }
                return date
            }
        }

        return nil
    }

    // MARK: - Unit Conversions

    /// All known normalized unit keys
    private static let allKnownUnits: Set<String> = [
        "mm", "cm", "m", "km", "in", "ft", "yd", "mi", "nmi",
        "mg", "g", "kg", "tonne", "oz", "lb", "st", "ton",
        "ml", "l", "gal", "qt", "pt", "cup", "floz", "tbsp", "tsp",
        "c", "f", "k",
        "mps", "kph", "kmh", "mph", "knots", "fps",
        "sqm", "sqkm", "sqft", "sqmi", "sqyd", "sqin", "acre", "hectare", "ha",
        "cumm", "cucm", "cum", "cukm", "cuin", "cuft", "cuyd",
        "ms", "sec", "s", "min", "hr", "h", "day", "week", "month", "year",
        "b", "kb", "mb", "gb", "tb", "pb",
    ]

    private static func isKnownUnit(_ str: String) -> Bool {
        allKnownUnits.contains(normalizeUnit(str))
    }

    /// Try to find a known unit at the end of a string, return (expression, unitName) or nil
    private static func splitExprAndUnit(_ str: String) -> (expr: String, unit: String)? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)

        // Try progressively longer suffixes (up to 3 words) as unit names
        let words = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        for count in 1...min(3, words.count) {
            let unitCandidate = words.suffix(count).joined(separator: " ")
            if isKnownUnit(unitCandidate) {
                let exprPart = words.dropLast(count).joined(separator: " ")
                return (exprPart, unitCandidate)
            }
        }

        // Try splitting number from attached unit: "100km", "5.5ft"
        if words.count == 1 {
            let word = trimmed
            if let match = word.range(of: #"^([\d.,]+)\s*([a-zA-Z°]+.*)$"#, options: .regularExpression) {
                let matched = String(word[match])
                let regex = try! NSRegularExpression(pattern: #"^([\d.,]+)\s*([a-zA-Z°]+.*)$"#)
                let nsRange = NSRange(matched.startIndex..., in: matched)
                if let r = regex.firstMatch(in: matched, range: nsRange),
                   let numRange = Range(r.range(at: 1), in: matched),
                   let unitRange = Range(r.range(at: 2), in: matched) {
                    let unit = String(matched[unitRange])
                    if isKnownUnit(unit) {
                        return (String(matched[numRange]), unit)
                    }
                }
            }
        }

        return nil
    }

    /// Evaluate a math expression string to a Double (handles x as multiply, parens, etc.)
    private static func evalMathToDouble(_ expr: String) -> Double? {
        var e = expr.trimmingCharacters(in: .whitespaces)
        guard !e.isEmpty else { return nil }

        // If it's just a number, parse directly
        if let v = parseNumber(e.replacingOccurrences(of: ",", with: "")) { return v }

        // Convert x/X to *
        while let range = e.range(of: #"([\d)])\s*[xX]\s*(?=[\d.(])"#, options: .regularExpression) {
            let matched = String(e[range])
            let replacement = String(matched.prefix(while: { $0 != "x" && $0 != "X" })) + "*"
            e.replaceSubrange(range, with: replacement)
        }

        e = e.replacingOccurrences(of: "^", with: "**")

        // Force float division
        e = e.replacingOccurrences(
            of: #"(?<![.\d])(\d+)(?![\d.])"#,
            with: "$1.0",
            options: .regularExpression
        )

        var resultNum: NSNumber?
        let ok = ObjCExceptionCatcher.catchException {
            let parsed = NSExpression(format: e)
            resultNum = parsed.expressionValue(with: nil, context: nil) as? NSNumber
        }
        guard ok, let num = resultNum else { return nil }
        let val = num.doubleValue
        if val.isNaN || val.isInfinite { return nil }
        return val
    }

    /// Length units that mark an "x"-list as dimensions rather than multiplication.
    private static let lengthUnitKeys: Set<String> = ["mm", "cm", "m", "km", "in", "ft", "yd", "mi", "nmi"]

    private static let metricLengthKeys: Set<String> = ["mm", "cm", "m", "km"]
    private static let cubicKeyFor: [String: String] = [
        "mm": "cumm", "cm": "cucm", "m": "cum", "km": "cukm",
        "in": "cuin", "ft": "cuft", "yd": "cuyd", "mi": "cumi",
    ]

    private struct ParsedDimensions {
        let values: [Double]
        let units: [String]      // resolved per-axis source units
        let sourceUnit: String   // first explicit unit (used for the volume row)
        let target: String       // resolved target length unit
        let uniformSource: Bool  // all axes share sourceUnit
    }

    /// Format with at most 2 decimals, trimming trailing zeros (0.1181→"0.12", 72.0→"72").
    private static func fmt2(_ d: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: d)) ?? String(format: "%.2f", d)
    }

    /// Like fmt2 but never collapses a non-zero value to "0": if 2 decimals would
    /// round to zero, fall back to enough decimals to show ~2 significant digits.
    private static func fmtNonZero(_ d: Double) -> String {
        let two = fmt2(d)
        if d == 0 || !(two == "0" || two == "-0") { return two }
        let magnitude = floor(log10(abs(d)))
        let decimals = max(2, Int(-magnitude) + 1)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = decimals
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: d)) ?? String(format: "%.\(decimals)f", d)
    }

    private static func parseDimensions(_ input: String) -> ParsedDimensions? {
        let lower = input.lowercased().trimmingCharacters(in: .whitespaces)

        // Optional explicit target: "... to in" / "... as cm"
        var body = lower
        var explicitTarget: String?
        for sep in [" to ", " as "] {
            if let range = lower.range(of: sep, options: .backwards) {
                let right = String(lower[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if isKnownUnit(right) {
                    body = String(lower[lower.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    explicitTarget = right
                    break
                }
            }
        }

        // Must be a separator-delimited list of 2+ parts. Prefer x/× (allows bare
        // operands that inherit the trailing unit). Fall back to "*" only when every
        // part carries its own explicit length unit — so "3*4*5" stays multiplication
        // but "32mm*45mm*67cm" is recognised as dimensions.
        let normalizedBody = body.replacingOccurrences(of: "×", with: "x")
        var rawParts = normalizedBody.components(separatedBy: "x")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var requireUnitOnEveryPart = false
        if rawParts.count < 2 && normalizedBody.contains("*") {
            rawParts = normalizedBody.components(separatedBy: "*")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            requireUnitOnEveryPart = true
        }
        guard rawParts.count >= 2 else { return nil }
        if requireUnitOnEveryPart {
            let allHaveLengthUnit = rawParts.allSatisfy { part in
                guard let (_, unit) = splitExprAndUnit(part) else { return false }
                return lengthUnitKeys.contains(normalizeUnit(unit))
            }
            guard allHaveLengthUnit else { return nil }
        }

        var values: [Double] = []
        var units: [String?] = []
        for part in rawParts {
            if let (exprStr, unit) = splitExprAndUnit(part) {
                let norm = normalizeUnit(unit)
                guard lengthUnitKeys.contains(norm), let v = evalMathToDouble(exprStr) else { return nil }
                values.append(v)
                units.append(norm)
            } else if let v = parseNumber(part.replacingOccurrences(of: ",", with: "")) {
                values.append(v)
                units.append(nil)
            } else {
                return nil
            }
        }

        let explicitUnits = units.compactMap { $0 }
        guard let sourceUnit = explicitUnits.first else { return nil }
        let resolvedUnits = units.map { $0 ?? sourceUnit }

        let target: String
        if let t = explicitTarget {
            let n = normalizeUnit(t)
            guard lengthUnitKeys.contains(n) else { return nil }
            target = n
        } else {
            target = metricLengthKeys.contains(sourceUnit) ? "in" : "mm"
        }

        return ParsedDimensions(
            values: values,
            units: resolvedUnits,
            sourceUnit: sourceUnit,
            target: target,
            uniformSource: resolvedUnits.allSatisfy { $0 == sourceUnit }
        )
    }

    /// Primary row for a dimension list: multiply the axes and convert the volume
    /// to cubic target units, e.g. "3mm x 4mm x 6mm to in" → "0.0044 in³".
    /// Mixed units (e.g. "32mm*45mm*67cm") are first normalised to the source unit.
    private static func evaluateDimensions(_ input: String) -> (expression: String, result: String)? {
        guard let d = parseDimensions(input),
              let cubicSrc = cubicKeyFor[d.sourceUnit] else { return nil }

        // Normalise every axis to the source unit, then multiply.
        var product: Double = 1
        for (v, u) in zip(d.values, d.units) {
            guard let inSource = convert(v, from: u, to: d.sourceUnit) else { return nil }
            product *= inSource
        }
        if d.target == d.sourceUnit {
            return (expression: input, result: "\(fmtNonZero(product)) \(d.sourceUnit)³")
        }
        guard let cubicDst = cubicKeyFor[d.target],
              let vol = convert(product, from: cubicSrc, to: cubicDst) else { return nil }
        return (expression: input, result: "\(fmtNonZero(vol)) \(d.target)³")
    }

    /// Secondary row: convert each axis individually, e.g.
    /// "3mm x 4mm x 6mm to in" → "0.12 × 0.16 × 0.24 in".
    static func secondaryResult(_ input: String) -> (expression: String, result: String)? {
        guard let d = parseDimensions(input) else { return nil }
        var converted: [String] = []
        for (v, u) in zip(d.values, d.units) {
            guard let c = convert(v, from: u, to: d.target) else { return nil }
            converted.append(fmt2(c))
        }
        return (expression: input, result: "\(converted.joined(separator: " × ")) \(d.target)")
    }

    /// When a dimension list uses a bare "m" — ambiguous between metres and "million" —
    /// also offer the pure-arithmetic reading: "1m x 1000" → "1,000,000 * 1,000 = 1,000,000,000".
    static func dimensionArithmetic(_ input: String) -> (expression: String, result: String)? {
        let lower = input.lowercased()
        // Must be an x/×-list AND contain a bare "m" (\dm\b — not "mm"/"cm").
        guard lower.range(of: #"[x×]"#, options: .regularExpression) != nil,
              lower.range(of: #"\dm\b"#, options: .regularExpression) != nil else { return nil }
        // Drop any "to <unit>" tail — arithmetic ignores it.
        var body = input
        for sep in [" to ", " as "] {
            if let r = body.lowercased().range(of: sep, options: .backwards) {
                body = String(body[body.startIndex..<r.lowerBound])
            }
        }
        // evaluateExpression converts x→* and (now) expands a bare "m" to million.
        guard let r = evaluateExpression(body) else { return nil }
        return (expression: normalizeExpression(body, expectedResult: r.result), result: r.result)
    }

    private static func evaluateUnitConversion(_ input: String) -> (expression: String, result: String)? {
        let lower = input.lowercased()

        // Split on " to " or " as " to find target unit
        var leftSide: String?
        var toUnit: String?

        for sep in [" to ", " as "] {
            if let range = lower.range(of: sep, options: .backwards) {
                let right = String(lower[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if isKnownUnit(right) {
                    leftSide = String(lower[lower.startIndex..<range.lowerBound])
                    toUnit = right
                    break
                }
            }
        }

        guard let left = leftSide, let target = toUnit else { return nil }

        // From the left side, extract source unit and expression
        guard let (exprStr, fromUnit) = splitExprAndUnit(left) else { return nil }

        let fromNorm = normalizeUnit(fromUnit)
        let toNorm = normalizeUnit(target)

        // Series: comma-separated or space-separated bare numbers → convert each
        let seriesParts: [String]
        if exprStr.contains(",") && !exprStr.contains("(") {
            seriesParts = exprStr.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            // Check if it's space-separated bare numbers (no operators)
            let tokens = exprStr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if tokens.count >= 2 && tokens.allSatisfy({ parseNumber($0.replacingOccurrences(of: ",", with: "")) != nil }) {
                seriesParts = tokens
            } else {
                seriesParts = []
            }
        }

        if !seriesParts.isEmpty {
            var results: [String] = []
            for part in seriesParts {
                guard let val = evalMathToDouble(part),
                      let conv = convert(val, from: fromNorm, to: toNorm) else { return nil }
                results.append(format(conv))
            }
            return (expression: input, result: "\(results.joined(separator: ", ")) \(target)")
        }

        // Evaluate expression as math, then convert
        guard let value = evalMathToDouble(exprStr) else { return nil }

        if let converted = convert(value, from: fromNorm, to: toNorm) {
            return (expression: input, result: "\(format(converted)) \(target)")
        }
        return nil
    }

    private static func convert(_ value: Double, from: String, to: String) -> Double? {
        // Normalize unit names
        let fromNorm = normalizeUnit(from)
        let toNorm = normalizeUnit(to)

        // Length
        let lengthToMeters: [String: Double] = [
            "mm": 0.001, "cm": 0.01, "m": 1, "km": 1000,
            "in": 0.0254, "ft": 0.3048, "yd": 0.9144, "mi": 1609.344,
            "nmi": 1852
        ]
        if let fromFactor = lengthToMeters[fromNorm], let toFactor = lengthToMeters[toNorm] {
            return value * fromFactor / toFactor
        }

        // Weight
        let weightToGrams: [String: Double] = [
            "mg": 0.001, "g": 1, "kg": 1000, "tonne": 1_000_000,
            "oz": 28.3495, "lb": 453.592, "st": 6350.29, "ton": 907_185
        ]
        if let fromFactor = weightToGrams[fromNorm], let toFactor = weightToGrams[toNorm] {
            return value * fromFactor / toFactor
        }

        // Volume
        let volumeToML: [String: Double] = [
            "ml": 1, "l": 1000, "gal": 3785.41, "qt": 946.353,
            "pt": 473.176, "cup": 236.588, "floz": 29.5735, "tbsp": 14.787, "tsp": 4.929
        ]
        if let fromFactor = volumeToML[fromNorm], let toFactor = volumeToML[toNorm] {
            return value * fromFactor / toFactor
        }

        // Temperature (special case)
        if (fromNorm == "c" || fromNorm == "f" || fromNorm == "k") &&
           (toNorm == "c" || toNorm == "f" || toNorm == "k") {
            return convertTemperature(value, from: fromNorm, to: toNorm)
        }

        // Speed
        let speedToMPS: [String: Double] = [
            "mps": 1, "kph": 0.277778, "kmh": 0.277778, "mph": 0.44704, "knots": 0.514444, "fps": 0.3048
        ]
        if let fromFactor = speedToMPS[fromNorm], let toFactor = speedToMPS[toNorm] {
            return value * fromFactor / toFactor
        }

        // Area
        let areaToSqM: [String: Double] = [
            "sqm": 1, "sqkm": 1_000_000, "sqft": 0.092903, "sqmi": 2_589_988,
            "sqyd": 0.836127, "acre": 4046.86, "hectare": 10_000, "ha": 10_000, "sqin": 0.00064516
        ]
        if let fromFactor = areaToSqM[fromNorm], let toFactor = areaToSqM[toNorm] {
            return value * fromFactor / toFactor
        }

        // Volume (cubic)
        let cubicToCuMM: [String: Double] = [
            "cumm": 1, "cucm": 1_000, "cum": 1_000_000_000, "cukm": 1e18,
            "cuin": 16_387.064, "cuft": 28_316_846.592, "cuyd": 764_554_857.984, "cumi": 4.168e18
        ]
        if let fromFactor = cubicToCuMM[fromNorm], let toFactor = cubicToCuMM[toNorm] {
            return value * fromFactor / toFactor
        }

        // Time
        let timeToSeconds: [String: Double] = [
            "ms": 0.001, "sec": 1, "s": 1, "min": 60, "hr": 3600, "h": 3600,
            "day": 86400, "week": 604_800, "month": 2_629_746, "year": 31_556_952
        ]
        if let fromFactor = timeToSeconds[fromNorm], let toFactor = timeToSeconds[toNorm] {
            return value * fromFactor / toFactor
        }

        // Data
        let dataToBytes: [String: Double] = [
            "b": 1, "kb": 1024, "mb": 1_048_576, "gb": 1_073_741_824,
            "tb": 1_099_511_627_776, "pb": 1_125_899_906_842_624
        ]
        if let fromFactor = dataToBytes[fromNorm], let toFactor = dataToBytes[toNorm] {
            return value * fromFactor / toFactor
        }

        return nil
    }

    private static func normalizeUnit(_ unit: String) -> String {
        let map: [String: String] = [
            // Length
            "millimeter": "mm", "millimeters": "mm", "millimetre": "mm", "millimetres": "mm",
            "centimeter": "cm", "centimeters": "cm", "centimetre": "cm", "centimetres": "cm",
            "meter": "m", "meters": "m", "metre": "m", "metres": "m",
            "kilometer": "km", "kilometers": "km", "kilometre": "km", "kilometres": "km",
            "inch": "in", "inches": "in", "\"": "in",
            "foot": "ft", "feet": "ft", "'": "ft",
            "yard": "yd", "yards": "yd",
            "mile": "mi", "miles": "mi",
            "nautical mile": "nmi", "nautical miles": "nmi",
            // Weight
            "milligram": "mg", "milligrams": "mg",
            "gram": "g", "grams": "g",
            "kilogram": "kg", "kilograms": "kg", "kilo": "kg", "kilos": "kg",
            "ounce": "oz", "ounces": "oz",
            "pound": "lb", "pounds": "lb", "lbs": "lb",
            "stone": "st", "stones": "st",
            "ton": "ton", "tons": "ton",
            "tonne": "tonne", "tonnes": "tonne",
            // Volume
            "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
            "liter": "l", "liters": "l", "litre": "l", "litres": "l",
            "gallon": "gal", "gallons": "gal",
            "quart": "qt", "quarts": "qt",
            "pint": "pt", "pints": "pt",
            "cup": "cup", "cups": "cup",
            "fluid ounce": "floz", "fluid ounces": "floz", "fl oz": "floz",
            "tablespoon": "tbsp", "tablespoons": "tbsp",
            "teaspoon": "tsp", "teaspoons": "tsp",
            // Temperature
            "celsius": "c", "fahrenheit": "f", "kelvin": "k",
            // Speed
            "km/h": "kph", "kmh": "kph", "km/hr": "kph",
            "mi/h": "mph", "mi/hr": "mph",
            "m/s": "mps",
            "ft/s": "fps",
            "knot": "knots",
            // Area
            "sq m": "sqm", "square meter": "sqm", "square meters": "sqm", "square metre": "sqm",
            "sq km": "sqkm", "square kilometer": "sqkm", "square kilometers": "sqkm",
            "sq ft": "sqft", "square foot": "sqft", "square feet": "sqft",
            "sq mi": "sqmi", "square mile": "sqmi", "square miles": "sqmi",
            "sq yd": "sqyd", "square yard": "sqyd", "square yards": "sqyd",
            "sq in": "sqin", "square inch": "sqin", "square inches": "sqin",
            "acre": "acre", "acres": "acre",
            "hectare": "hectare", "hectares": "hectare",
            // Cubic / Volume
            "mm3": "cumm", "mm³": "cumm", "cu mm": "cumm", "cubic mm": "cumm",
            "cubic millimeter": "cumm", "cubic millimeters": "cumm", "cubic millimetre": "cumm", "cubic millimetres": "cumm",
            "cm3": "cucm", "cm³": "cucm", "cu cm": "cucm", "cubic cm": "cucm", "cc": "cucm",
            "cubic centimeter": "cucm", "cubic centimeters": "cucm", "cubic centimetre": "cucm", "cubic centimetres": "cucm",
            "m3": "cum", "m³": "cum", "cu m": "cum", "cubic m": "cum",
            "cubic meter": "cum", "cubic meters": "cum", "cubic metre": "cum", "cubic metres": "cum",
            "km3": "cukm", "km³": "cukm", "cu km": "cukm", "cubic km": "cukm",
            "cubic kilometer": "cukm", "cubic kilometers": "cukm",
            "in3": "cuin", "in³": "cuin", "cu in": "cuin", "cubic in": "cuin",
            "cubic inch": "cuin", "cubic inches": "cuin",
            "ft3": "cuft", "ft³": "cuft", "cu ft": "cuft", "cubic ft": "cuft",
            "cubic foot": "cuft", "cubic feet": "cuft",
            "yd3": "cuyd", "yd³": "cuyd", "cu yd": "cuyd", "cubic yd": "cuyd",
            "cubic yard": "cuyd", "cubic yards": "cuyd",
            // Time
            "millisecond": "ms", "milliseconds": "ms",
            "second": "sec", "seconds": "sec", "secs": "sec",
            "minute": "min", "minutes": "min", "mins": "min",
            "hour": "hr", "hours": "hr", "hrs": "hr",
            "day": "day", "days": "day",
            "week": "week", "weeks": "week",
            "month": "month", "months": "month",
            "year": "year", "years": "year",
            // Data
            "byte": "b", "bytes": "b",
            "kilobyte": "kb", "kilobytes": "kb",
            "megabyte": "mb", "megabytes": "mb",
            "gigabyte": "gb", "gigabytes": "gb",
            "terabyte": "tb", "terabytes": "tb",
            "petabyte": "pb", "petabytes": "pb",
        ]

        let lower = unit.lowercased()
        return map[lower] ?? lower
    }

    private static func convertTemperature(_ value: Double, from: String, to: String) -> Double? {
        // Convert to Celsius first
        var celsius: Double
        switch from {
        case "c": celsius = value
        case "f": celsius = (value - 32) * 5.0 / 9.0
        case "k": celsius = value - 273.15
        default: return nil
        }

        // Convert from Celsius to target
        switch to {
        case "c": return celsius
        case "f": return celsius * 9.0 / 5.0 + 32
        case "k": return celsius + 273.15
        default: return nil
        }
    }

    // MARK: - Currency Conversions

    private static var exchangeRates: [String: Double] = [:]
    private static var ratesLastFetched: Date?

    private static let currencyNames: [String: String] = [
        "dollar": "usd", "dollars": "usd", "usd": "usd", "$": "usd",
        "euro": "eur", "euros": "eur", "eur": "eur",
        "pound": "gbp", "pounds": "gbp", "gbp": "gbp", "sterling": "gbp",
        "yen": "jpy", "jpy": "jpy",
        "cad": "cad", "canadian": "cad", "canadian dollar": "cad", "canadian dollars": "cad",
        "aud": "aud", "australian": "aud", "australian dollar": "aud", "australian dollars": "aud",
        "chf": "chf", "swiss franc": "chf", "franc": "chf", "francs": "chf",
        "cny": "cny", "yuan": "cny", "rmb": "cny", "renminbi": "cny",
        "inr": "inr", "rupee": "inr", "rupees": "inr",
        "krw": "krw", "won": "krw",
        "mxn": "mxn", "peso": "mxn", "pesos": "mxn",
        "brl": "brl", "real": "brl", "reais": "brl",
        "sek": "sek", "krona": "sek",
        "nok": "nok",
        "dkk": "dkk",
        "sgd": "sgd",
        "hkd": "hkd",
        "nzd": "nzd",
        "ils": "ils", "shekel": "ils", "shekels": "ils", "nis": "ils",
        "aed": "aed", "dirham": "aed", "dirhams": "aed",
        "zar": "zar", "rand": "zar",
        "try": "try", "lira": "try",
        "thb": "thb", "baht": "thb",
        "pln": "pln", "zloty": "pln",
        "php": "php",
        "idr": "idr", "rupiah": "idr",
        "twd": "twd",
        "czk": "czk",
        "clp": "clp",
        "cop": "cop",
    ]

    private static func evaluateCurrency(_ input: String) -> (expression: String, result: String)? {
        let lower = input.lowercased()

        // Pattern: "<number><currency> to/in <currency>" (space optional between number and currency)
        let regex = try! NSRegularExpression(pattern: #"^([\d.,]+)\s*(.+?)\s+(?:to|in)\s+(.+)$"#)
        let nsRange = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: nsRange) else { return nil }

        let numStr = String(lower[Range(match.range(at: 1), in: lower)!]).replacingOccurrences(of: ",", with: "")
        let fromStr = String(lower[Range(match.range(at: 2), in: lower)!]).trimmingCharacters(in: .whitespaces)
        let toStr = String(lower[Range(match.range(at: 3), in: lower)!]).trimmingCharacters(in: .whitespaces)

        guard let value = parseNumber(numStr),
              let fromCurrency = currencyNames[fromStr],
              let toCurrency = currencyNames[toStr] else { return nil }

        // Check if we have rates cached
        if let rates = getCachedRates(),
           let fromRate = rates[fromCurrency],
           let toRate = rates[toCurrency] {
            let converted = value / fromRate * toRate
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.maximumFractionDigits = 2
            fmt.minimumFractionDigits = 2
            fmt.usesGroupingSeparator = true
            let formatted = fmt.string(from: NSNumber(value: converted)) ?? String(format: "%.2f", converted)
            return (expression: input, result: "\(formatted) \(toCurrency.uppercased())")
        }

        // Fetch rates async, return placeholder
        fetchRates()
        return (expression: input, result: "Loading rates...")
    }

    private static func getCachedRates() -> [String: Double]? {
        guard !exchangeRates.isEmpty else { return nil }
        // Rates are valid for 1 hour
        if let lastFetched = ratesLastFetched, Date().timeIntervalSince(lastFetched) < 3600 {
            return exchangeRates
        }
        return exchangeRates.isEmpty ? nil : exchangeRates
    }

    static func fetchRates() {
        guard ratesLastFetched == nil || Date().timeIntervalSince(ratesLastFetched!) > 3600 else { return }

        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rates = json["rates"] as? [String: Double] {
                DispatchQueue.main.async {
                    var normalized: [String: Double] = [:]
                    for (key, val) in rates {
                        normalized[key.lowercased()] = val
                    }
                    exchangeRates = normalized
                    ratesLastFetched = Date()
                }
            }
        }.resume()
    }

    // MARK: - Auto Currency Conversion (standalone amounts to USD)

    private static func evaluateAutoCurrencyConvert(_ input: String) -> (expression: String, result: String)? {
        let lower = input.lowercased().trimmingCharacters(in: .whitespaces)

        // Pattern: "<number><currency>" or "<number> <currency>" or "<symbol><number>"
        // e.g. "1rmb", "100 eur", "100eur", "€50", "£30"
        let patterns: [(regex: String, numGroup: Int, curGroup: Int)] = [
            (#"^([\d,.]+)\s*([a-z]{2,})\s*$"#, 1, 2),             // "100eur" or "100 eur"
            (#"^([\$€£¥₪])\s*([\d,.]+)\s*$"#, 2, 1),              // "$100", "€50"
        ]

        for p in patterns {
            let regex = try! NSRegularExpression(pattern: p.regex, options: .caseInsensitive)
            let nsRange = NSRange(lower.startIndex..., in: lower)
            guard let match = regex.firstMatch(in: lower, range: nsRange) else { continue }

            let numStr = String(lower[Range(match.range(at: p.numGroup), in: lower)!]).replacingOccurrences(of: ",", with: "")
            let curStr = String(lower[Range(match.range(at: p.curGroup), in: lower)!]).lowercased()

            guard let value = parseNumber(numStr),
                  let fromCurrency = currencyNames[curStr],
                  fromCurrency != "usd" else { continue }  // Don't convert USD to USD

            if let rates = getCachedRates(),
               let fromRate = rates[fromCurrency],
               let toRate = rates["usd"] {
                let converted = value / fromRate * toRate
                let fmt = NumberFormatter()
                fmt.numberStyle = .decimal
                fmt.maximumFractionDigits = 2
                fmt.minimumFractionDigits = 2
                fmt.usesGroupingSeparator = true
                let formatted = fmt.string(from: NSNumber(value: converted)) ?? String(format: "%.2f", converted)
                return (expression: input, result: "$\(formatted)")
            }

            fetchRates()
            return (expression: input, result: "Loading rates...")
        }

        return nil
    }

    // MARK: - Auto Unit Conversion (metric to US standard)

    private static let metricToUS: [(from: String, to: String, label: String)] = [
        ("km", "mi", "miles"), ("m", "ft", "ft"), ("cm", "in", "in"), ("mm", "in", "in"),
        ("kg", "lb", "lbs"), ("g", "oz", "oz"),
        ("l", "gal", "gal"), ("ml", "floz", "fl oz"),
        ("c", "f", "F"),
        ("kph", "mph", "mph"), ("kmh", "mph", "mph"),
        ("sqm", "sqft", "sq ft"), ("sqkm", "sqmi", "sq mi"),
        ("hectare", "acre", "acres"), ("ha", "acre", "acres"),
        ("cumm", "cuin", "cu in"), ("cucm", "cuin", "cu in"),
        ("cum", "cuft", "cu ft"), ("cukm", "cumi", "cu mi"),
    ]

    private static func evaluateAutoUnitConvert(_ input: String) -> (expression: String, result: String)? {
        let lower = input.lowercased().trimmingCharacters(in: .whitespaces)

        // Make sure there's no "to" or "in" (that's handled by explicit conversion)
        guard !lower.contains(" to "), !lower.contains(" in "), !lower.contains(" as ") else { return nil }

        // Pattern: "<number><unit>" or "<number> <unit>" (space optional)
        let regex = try! NSRegularExpression(pattern: #"^([\d,.]+)\s*([a-z/°]+.*)$"#)
        let nsRange = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: nsRange) else { return nil }

        let numStr = String(lower[Range(match.range(at: 1), in: lower)!]).replacingOccurrences(of: ",", with: "")
        let unitStr = String(lower[Range(match.range(at: 2), in: lower)!]).trimmingCharacters(in: .whitespaces)

        guard let value = parseNumber(numStr) else { return nil }

        let normalized = normalizeUnit(unitStr)

        for mapping in metricToUS {
            if normalized == mapping.from {
                if let converted = convert(value, from: mapping.from, to: mapping.to) {
                    return (expression: input, result: "\(format(converted)) \(mapping.label)")
                }
            }
        }

        return nil
    }

    // MARK: - Equation Solver

    private static func evaluateEquation(_ input: String) -> (expression: String, result: String)? {
        var trimmed = input.trimmingCharacters(in: .whitespaces)

        // Strip trailing "solve for x", "solve", "find x"
        trimmed = trimmed.replacingOccurrences(
            of: #"\s*,?\s*(solve\s*(for\s*x)?|find\s*x)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        guard trimmed.contains("=") else { return nil }
        let sides = trimmed.components(separatedBy: "=")
        guard sides.count == 2 else { return nil }

        let lhs = sides[0].trimmingCharacters(in: .whitespaces)
        let rhs = sides[1].trimmingCharacters(in: .whitespaces)
        guard !lhs.isEmpty, !rhs.isEmpty else { return nil }

        // Must contain x as a variable (not part of a word like sqrt, max, exp)
        let varPat = #"(?<![a-zA-Z])x(?![a-zA-Z])"#
        let hasVar = lhs.range(of: varPat, options: .regularExpression) != nil ||
                     rhs.range(of: varPat, options: .regularExpression) != nil
        guard hasVar else { return nil }

        // f(x) = LHS - RHS; solve for f(x) = 0
        func evalAt(_ xVal: Double) -> Double? {
            guard let l = evalSide(lhs, x: xVal), let r = evalSide(rhs, x: xVal) else { return nil }
            return l - r
        }

        // Newton's method from multiple starting points
        let h = 1e-8
        var solutions: [Double] = []
        let starts: [Double] = [0.5, -0.5, 1, -1, 2, -2, 5, -5, 10, -10, 50, -50, 100, -100, 0.01, -0.01]

        for x0 in starts {
            var x = x0
            var converged = false
            for _ in 0..<300 {
                guard let fx = evalAt(x) else { break }
                if abs(fx) < 1e-10 { converged = true; break }
                guard let fxp = evalAt(x + h), let fxm = evalAt(x - h) else { break }
                let deriv = (fxp - fxm) / (2 * h)
                if abs(deriv) < 1e-15 { break }
                let step = fx / deriv
                x -= step
                if abs(step) < 1e-12 { converged = true; break }
                if abs(x) > 1e15 { break }
            }
            if converged {
                let rounded = (x * 1e9).rounded() / 1e9
                let clean = rounded == 0 ? 0.0 : rounded
                if !solutions.contains(where: { abs($0 - clean) < 1e-6 }) {
                    solutions.append(clean)
                }
            }
        }

        guard !solutions.isEmpty else { return (expression: trimmed, result: "No solution found") }

        let formatted = solutions.sorted().map { "x = \(format($0))" }
        return (expression: trimmed, result: formatted.joined(separator: "  or  "))
    }

    /// Evaluate one side of an equation with x substituted
    private static func evalSide(_ expr: String, x xVal: Double) -> Double? {
        var e = expr

        // Implicit multiplication around x variable
        e = e.replacingOccurrences(of: #"(\d)\s*x(?![a-zA-Z])"#, with: "$1*x", options: .regularExpression)
        e = e.replacingOccurrences(of: #"(?<![a-zA-Z])x\s*(\d)"#, with: "x*$1", options: .regularExpression)
        e = e.replacingOccurrences(of: #"\)\s*x(?![a-zA-Z])"#, with: ")*x", options: .regularExpression)
        e = e.replacingOccurrences(of: #"(?<![a-zA-Z])x\s*\("#, with: "x*(", options: .regularExpression)

        // Substitute x with value (wrapped in parens for safety with negatives)
        e = e.replacingOccurrences(of: #"(?<![a-zA-Z])x(?![a-zA-Z])"#, with: "(\(xVal))", options: .regularExpression)

        // Same preprocessing as evaluateExpression
        e = expandAbbreviations(e)
        e = e.replacingOccurrences(of: #"[\$€£¥₪]"#, with: "", options: .regularExpression)
        e = e.replacingOccurrences(of: #"√\s*\(([^)]+)\)"#, with: "sqrt($1)", options: .regularExpression)
        e = e.replacingOccurrences(of: #"√\s*([\d.]+)"#, with: "sqrt($1)", options: .regularExpression)
        e = e.replacingOccurrences(of: "^", with: "**")

        // Force floating-point division
        e = e.replacingOccurrences(of: #"(?<![.\d])(\d+)(?![\d.])"#, with: "$1.0", options: .regularExpression)

        let trimmedExpr = e.trimmingCharacters(in: .whitespaces)
        guard !trimmedExpr.isEmpty else { return nil }

        var resultNum: NSNumber?
        let ok = ObjCExceptionCatcher.catchException {
            let parsed = NSExpression(format: trimmedExpr)
            resultNum = parsed.expressionValue(with: nil, context: nil) as? NSNumber
        }
        guard ok, let result = resultNum else { return nil }
        let val = result.doubleValue
        if val.isNaN || val.isInfinite { return nil }
        return val
    }

    // MARK: - Standard Math Expression

    private static func evaluateExpression(_ input: String) -> (expression: String, result: String)? {
        var expr = input
        // Strip currency symbols and "~" (approximately) up front so they don't block the
        // "x"→"*" conversion (e.g. "18 x ~$.70" — both sat between "x" and the number).
        expr = expr.replacingOccurrences(of: #"[\$€£¥₪~]"#, with: "", options: .regularExpression)
        // Convert x/X to * (multiply) — loop since matches can overlap (e.g. "2x3x4")
        while let range = expr.range(of: #"([\d\w)])\s*[xX]\s*(?=[\d.(])"#, options: .regularExpression) {
            let matched = String(expr[range])
            let replacement = String(matched.prefix(while: { $0 != "x" && $0 != "X" })) + "*"
            expr.replaceSubrange(range, with: replacement)
        }
        expr = expandAbbreviations(expr)
        // Strip thousands-separator commas (digit,digit patterns)
        expr = expr.replacingOccurrences(of: #"(\d),(\d)"#, with: "$1$2", options: .regularExpression)
        // √25 or √ 25 or √(25) -> sqrt(25)
        expr = expr.replacingOccurrences(
            of: #"√\s*\(([^)]+)\)"#,
            with: "sqrt($1)",
            options: .regularExpression
        )
        expr = expr.replacingOccurrences(
            of: #"√\s*([\d.]+)"#,
            with: "sqrt($1)",
            options: .regularExpression
        )
        expr = expr.replacingOccurrences(of: "^", with: "**")

        // Convert a trailing "N%" into "(N*0.01)" so "925x12%" -> 925*0.12 = 111.
        // Only when % is NOT immediately followed by a digit or "(" (that's modulo, e.g. "10%3").
        expr = expr.replacingOccurrences(
            of: #"([\d.]+)\s*%(?!\s*[\d.(])"#,
            with: "($1*0.01)",
            options: .regularExpression
        )

        // Remove parenthetical annotations: "(...)" that contain a letter but no math
        // operator — e.g. "(hard 2 piece box)" is a note, not "(2 + 3)". Done before
        // token stripping so a bare number inside the note doesn't get left behind.
        expr = expr.replacingOccurrences(
            of: #"\([^()+\-*/^]*[a-zA-Z][^()+\-*/^]*\)"#,
            with: "",
            options: .regularExpression
        )

        let mathChars = CharacterSet(charactersIn: "+-*/%()")
        let mathFunctions = ["sqrt", "log", "ln", "abs", "ceil", "floor"]

        // Strip stray "label" words (e.g. "fob" in "5.22 fob x 12") that aren't math
        // functions, so annotated expressions still evaluate. Runs after abbreviation
        // expansion, so "4k"/"5m" are already numeric. The label survives in the copied
        // text because normalizeExpression keeps the original string.
        if expr.range(of: #"[a-zA-Z]"#, options: .regularExpression) != nil {
            expr = stripLabelWords(expr)
        }

        // Implicit multiplication: "10(1-.43)" → "10*(1-.43)", "(2)(3)" → "(2)*(3)",
        // "(1-.43)10" → "(1-.43)*10". A leading "+"/"-" before "(" still binds as the
        // operator (e.g. "1 + (2)") because we require a digit or ")" immediately before.
        expr = expr.replacingOccurrences(
            of: #"([\d)])\s*\("#,
            with: "$1*(",
            options: .regularExpression
        )
        expr = expr.replacingOccurrences(
            of: #"\)\s*(\d)"#,
            with: ")*$1",
            options: .regularExpression
        )

        let hasMathOp = expr.unicodeScalars.contains(where: { mathChars.contains($0) })
        let hasMathFunc = mathFunctions.contains(where: { expr.lowercased().contains($0) })
        guard hasMathOp || hasMathFunc else { return nil }

        // Force floating-point division: convert integer literals to doubles
        // "7/5" -> "7.0/5.0" so NSExpression doesn't do integer division
        // Lookbehind ensures we don't touch digits after a decimal point (10.6 stays 10.6, not 10.6.0)
        expr = expr.replacingOccurrences(
            of: #"(?<![.\d])(\d+)(?![\d.])"#,
            with: "$1.0",
            options: .regularExpression
        )

        // Reject obviously malformed expressions that would crash NSExpression
        let trimmedExpr = expr.trimmingCharacters(in: .whitespaces)
        if trimmedExpr.hasSuffix("+") || trimmedExpr.hasSuffix("-") ||
           trimmedExpr.hasSuffix("*") || trimmedExpr.hasSuffix("/") ||
           trimmedExpr.hasSuffix(".") || trimmedExpr.hasSuffix("(") ||
           trimmedExpr.hasPrefix("*") || trimmedExpr.hasPrefix("/") {
            return nil
        }
        // Reject lone dots, empty parens, double operators (but allow ** for power)
        if trimmedExpr.range(of: #"\.\s*[+\-*/)]"#, options: .regularExpression) != nil { return nil }
        let nopower = trimmedExpr.replacingOccurrences(of: "**", with: "POWER")
        if nopower.range(of: #"[+\-*/]\s*[+*/]"#, options: .regularExpression) != nil { return nil }
        if trimmedExpr.contains("()") { return nil }

        // Use ObjC exception catcher — NSExpression throws ObjC exceptions, not Swift errors
        var resultNum: NSNumber?
        let ok = ObjCExceptionCatcher.catchException {
            let parsed = NSExpression(format: trimmedExpr)
            resultNum = parsed.expressionValue(with: nil, context: nil) as? NSNumber
        }

        guard ok, let result = resultNum else { return nil }
        let doubleVal = result.doubleValue
        if doubleVal.isNaN || doubleVal.isInfinite {
            return (expression: input, result: "Error")
        }
        guard let formatted = formatter.string(from: result) else { return nil }

        // Margin formula ("1 - cost/sell" = 25.00%): if input is `1 - <expr>/<expr>`,
        // format the result as a percentage with 2 decimals.
        let inputTrim = input.trimmingCharacters(in: .whitespaces)
        if inputTrim.range(of: #"^1\s*-.*/.*$"#, options: .regularExpression) != nil {
            let pctFmt = NumberFormatter()
            pctFmt.numberStyle = .decimal
            pctFmt.minimumFractionDigits = 2
            pctFmt.maximumFractionDigits = 2
            pctFmt.usesGroupingSeparator = true
            let pctStr = pctFmt.string(from: NSNumber(value: doubleVal * 100)) ?? String(format: "%.2f", doubleVal * 100)
            return (expression: input, result: "\(pctStr)%")
        }

        // If the input contains a currency symbol anywhere (e.g. "18 x $.70"), prefix the
        // result with that symbol and round to 2 decimals.
        if let symbol = input.first(where: { "$€£¥₪".contains($0) }) {
            let currencyFmt = NumberFormatter()
            currencyFmt.numberStyle = .decimal
            currencyFmt.minimumFractionDigits = 2
            currencyFmt.maximumFractionDigits = 2
            currencyFmt.usesGroupingSeparator = true
            let rounded = currencyFmt.string(from: NSNumber(value: doubleVal)) ?? formatted
            return (expression: input, result: String(symbol) + rounded)
        }
        return (expression: input, result: formatted)
    }

    // MARK: - UPC / GTIN Check Digit

    /// Computes the GS1 mod-10 check digit for a barcode payload missing its final digit.
    /// Accepts 11/12/13-digit payloads (with optional spaces/dashes) → UPC-A / EAN-13 / GTIN-14.
    private static func evaluateCheckDigit(_ input: String) -> (expression: String, result: String)? {
        let digits = input.filter { $0.isNumber }
        // Only treat as a barcode if the input was purely digits + optional separators.
        let allowed = CharacterSet(charactersIn: "0123456789 -")
        guard input.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        let label: String
        switch digits.count {
        case 11: label = "UPC-A"
        case 12: label = "EAN-13"
        case 13: label = "GTIN-14"
        default: return nil
        }

        let nums = digits.compactMap { $0.wholeNumberValue }
        guard nums.count == digits.count else { return nil }

        // GS1: weight digits 3,1,3,1… from the rightmost payload digit.
        var sum = 0
        for (i, d) in nums.reversed().enumerated() {
            sum += d * (i % 2 == 0 ? 3 : 1)
        }
        let check = (10 - (sum % 10)) % 10
        let full = digits + String(check)
        return (expression: "\(label) check digit: \(check)", result: full)
    }

    // MARK: - Standalone Abbreviation

    private static func evaluateAbbreviation(_ input: String) -> (expression: String, result: String)? {
        let s = input.lowercased().replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        let pattern = #"^([\d.]+)\s*(k|mil|milion|million|m|billion|bil|b|trillion|tril|t)$"#
        guard s.range(of: pattern, options: .regularExpression) != nil,
              let value = parseNumber(s), value != Double(s) else { return nil }
        return (expression: input, result: format(value))
    }

    // MARK: - Number Abbreviation Parsing

    /// Parses a numeric string, expanding abbreviations like "5k", "2.5mil", "1billion"
    private static func parseNumber(_ str: String) -> Double? {
        let s = str.lowercased().trimmingCharacters(in: .whitespaces)
        // Match: optional number followed by abbreviation suffix
        let pattern = #"^([\d,.]+)\s*(k|mil|milion|million|m|billion|bil|b|trillion|tril|t)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let numRange = Range(match.range(at: 1), in: s),
              let suffRange = Range(match.range(at: 2), in: s) else {
            return Double(str.replacingOccurrences(of: ",", with: ""))
        }
        let numStr = String(s[numRange]).replacingOccurrences(of: ",", with: "")
        let suffix = String(s[suffRange])
        guard let base = Double(numStr) else { return nil }
        switch suffix {
        case "k": return base * 1_000
        case "m", "mil", "milion", "million": return base * 1_000_000
        case "b", "bil", "billion": return base * 1_000_000_000
        case "t", "tril", "trillion": return base * 1_000_000_000_000
        default: return base
        }
    }

    /// Expands abbreviations inline within an expression string (e.g. "5k + 2m" -> "5000 + 2000000")
    private static func expandAbbreviations(_ expr: String) -> String {
        // Single-letter m/b/t only expand here (math-expression context, operator required),
        // so they don't clash with "m" = meters in unit conversions. Longest alternatives
        // first; the trailing \b also stops "m" from matching inside "million".
        let pattern = #"(\d[\d,.]*)\s*(k|million|milion|mil|m|billion|bil|b|trillion|tril|t)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return expr }
        var result = expr
        // Process matches from end to preserve ranges
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let numRange = Range(match.range(at: 1), in: result),
                  let suffRange = Range(match.range(at: 2), in: result) else { continue }
            let numStr = String(result[numRange]).replacingOccurrences(of: ",", with: "")
            let suffix = String(result[suffRange]).lowercased()
            guard let base = Double(numStr) else { continue }
            let multiplier: Double
            switch suffix {
            case "k": multiplier = 1_000
            case "m", "mil", "milion", "million": multiplier = 1_000_000
            case "b", "bil", "billion": multiplier = 1_000_000_000
            case "t", "tril", "trillion": multiplier = 1_000_000_000_000
            default: continue
            }
            let expanded = base * multiplier
            // Use integer format if whole number
            let expandedStr = expanded == expanded.rounded() ? String(Int(expanded)) : String(expanded)
            result.replaceSubrange(fullRange, with: expandedStr)
        }
        return result
    }

    private static let mathFunctionNames: Set<String> = ["sqrt", "log", "ln", "abs", "ceil", "floor"]

    /// Character ranges of "label" tokens to remove from a math string.
    /// A label is an alphanumeric run containing ≥1 letter that isn't a math function,
    /// number abbreviation (4k), or the multiply "x". A label also absorbs TIGHT
    /// hyphen-joined parts so a model number like "DC-124" / "DC-124-RD" is dropped
    /// whole — but a spaced "DC - 124" keeps the "-" as subtraction.
    private static func labelRanges(in expr: String) -> [NSRange] {
        let abbrevPattern = #"^[\d.,]+(k|million|milion|mil|m|billion|bil|b|trillion|tril|t)$"#
        guard let tokenRegex = try? NSRegularExpression(pattern: #"[a-zA-Z0-9]*[a-zA-Z][a-zA-Z0-9]*"#),
              let contRegex = try? NSRegularExpression(pattern: #"^-[a-zA-Z0-9]+"#) else { return [] }
        let ns = expr as NSString
        var ranges: [NSRange] = []
        var consumedUpTo = 0
        for m in tokenRegex.matches(in: expr, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location < consumedUpTo { continue }
            let token = ns.substring(with: m.range)
            let lower = token.lowercased()
            let lettersOnlyX = token.filter { $0.isLetter }.allSatisfy { $0 == "x" }
            let isAbbrev = lower.range(of: abbrevPattern, options: .regularExpression) != nil
            guard !mathFunctionNames.contains(lower), !isAbbrev, !lettersOnlyX else { continue }
            // Extend across hyphen-joined model-number continuations.
            var end = m.range.location + m.range.length
            while end < ns.length,
                  let cm = contRegex.firstMatch(in: expr, range: NSRange(location: end, length: ns.length - end)) {
                end += cm.range.length
            }
            ranges.append(NSRange(location: m.range.location, length: end - m.range.location))
            consumedUpTo = end
        }
        return ranges
    }

    /// Remove label tokens (see labelRanges) so an annotated expression still evaluates.
    private static func stripLabelWords(_ expr: String) -> String {
        let ranges = labelRanges(in: expr)
        guard !ranges.isEmpty else { return expr }
        let ns = expr as NSString
        var result = ""
        var cursor = 0
        for r in ranges {
            result += ns.substring(with: NSRange(location: cursor, length: r.location - cursor))
            cursor = r.location + r.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Builds a styled version of a math input where stripped "label" tokens are
    /// struck through and dimmed, while the parts that actually get calculated stay
    /// solid. Returns nil if there are no labels (nothing to highlight).
    static func labelHighlightedExpression(_ input: String) -> AttributedString? {
        let ranges = labelRanges(in: input)
        guard !ranges.isEmpty else { return nil }
        let ns = input as NSString
        var attr = AttributedString()
        var cursor = 0
        for r in ranges {
            var normal = AttributedString(ns.substring(with: NSRange(location: cursor, length: r.location - cursor)))
            normal.foregroundColor = .primary
            attr += normal

            var label = AttributedString(ns.substring(with: r))
            label.strikethroughStyle = .single
            label.foregroundColor = .secondary
            attr += label
            cursor = r.location + r.length
        }
        var tail = AttributedString(ns.substring(from: cursor))
        tail.foregroundColor = .primary
        attr += tail
        return attr
    }

    // MARK: - Expression Normalization

    /// Produce a clean, human-readable version of a math expression for copying:
    /// "7kx5.8k/4million" → "7,000 * 5,800 / 4,000,000". Expands abbreviations,
    /// converts x→*, and adds thousands separators. Returns the original input if
    /// the normalized form no longer evaluates to `expectedResult` (so non-arithmetic
    /// inputs like unit conversions are left untouched).
    static func normalizeExpression(_ input: String, expectedResult: String) -> String {
        var e = input
        // Convert x/X to *
        while let range = e.range(of: #"([\d\w)])\s*[xX]\s*(?=[\d.(])"#, options: .regularExpression) {
            let matched = String(e[range])
            let replacement = String(matched.prefix(while: { $0 != "x" && $0 != "X" })) + "*"
            e.replaceSubrange(range, with: replacement)
        }
        e = expandAbbreviations(e)
        // Strip any existing thousands commas, then re-group all numbers.
        e = e.replacingOccurrences(of: #"(\d),(\d)"#, with: "$1$2", options: .regularExpression)
        e = addThousandsSeparators(e)
        // Space out operators.
        e = e.replacingOccurrences(of: #"\s*([+\-*/])\s*"#, with: " $1 ", options: .regularExpression)
        e = e.trimmingCharacters(in: .whitespaces)

        // Only use the normalized form if it still evaluates to the same answer.
        if let check = evaluate(e), check.result == expectedResult {
            return e
        }
        return input
    }

    private static func addThousandsSeparators(_ s: String) -> String {
        // Match a full number including leading-dot decimals (".5593") so the fractional
        // part never gets a thousands comma.
        guard let regex = try? NSRegularExpression(pattern: #"\d+\.\d+|\.\d+|\d+"#) else { return s }
        let ns = s as NSString
        var result = ""
        var lastEnd = 0
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
            result += groupNumber(ns.substring(with: m.range))
            lastEnd = m.range.location + m.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }

    /// Group only the integer part with thousands separators; leave the fractional part
    /// untouched (and don't touch leading-dot decimals like ".5593").
    private static func groupNumber(_ numStr: String) -> String {
        let comps = numStr.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let intPart = comps[0]
        guard !intPart.isEmpty, let intVal = Int(intPart) else { return numStr }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        guard let grouped = f.string(from: NSNumber(value: intVal)) else { return numStr }
        return comps.count > 1 ? "\(grouped).\(comps[1])" : grouped
    }

    // MARK: - Formatting

    private static func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return formatter.string(from: NSNumber(value: Int(value))) ?? String(Int(value))
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
