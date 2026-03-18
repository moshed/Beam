import Foundation

struct MathEvaluator {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 10
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()

    static func evaluate(_ input: String) -> (expression: String, result: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Try currency-aware math first (e.g. "$6 $7 $8.9", "$1 + 1eur", "add $5 $10")
        if let currMathResult = evaluateCurrencyMath(trimmed) {
            return currMathResult
        }

        // Try natural language math first
        if let nlResult = evaluateNaturalLanguage(trimmed) {
            return nlResult
        }

        // Try date calculations
        if let dateResult = evaluateDate(trimmed) {
            return dateResult
        }

        // Try unit conversions
        if let unitResult = evaluateUnitConversion(trimmed) {
            return unitResult
        }

        // Try currency conversions (explicit "X to Y")
        if let currencyResult = evaluateCurrency(trimmed) {
            return currencyResult
        }

        // Auto-convert standalone currency to USD (e.g. "1 rmb" -> "$0.14")
        if let autoResult = evaluateAutoCurrencyConvert(trimmed) {
            return autoResult
        }

        // Auto-convert standalone units to US standard
        if let autoUnit = evaluateAutoUnitConvert(trimmed) {
            return autoUnit
        }

        // Standard math expression
        return evaluateExpression(trimmed)
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
        let trimmed = input.trimmingCharacters(in: .whitespaces)

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

        // Split into tokens by + or whitespace
        let cleanInput = working
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

        // Second pass: parse all tokens (currency-tagged and bare numbers)
        // Match: symbol+number, number+code, or bare number
        let tokenPattern = #"([\$€£¥₪])\s*([\d,.]+)|([\d,.]+)\s*([a-zA-Z₪€£¥\$]{2,3})|([\d,.]+)"#
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

        for match in matches {
            var amount: Double?
            var currency: String?

            // Pattern 1: symbol + number (e.g. "$5")
            if match.range(at: 1).location != NSNotFound,
               let symRange = Range(match.range(at: 1), in: cleanNoComma),
               let numRange = Range(match.range(at: 2), in: cleanNoComma) {
                let sym = String(cleanNoComma[symRange])
                let num = String(cleanNoComma[numRange])
                currency = currencySymbols[sym]
                amount = Double(num)
            }
            // Pattern 2: number + code (e.g. "5eur")
            else if match.range(at: 3).location != NSNotFound,
                    let numRange = Range(match.range(at: 3), in: cleanNoComma),
                    let codeRange = Range(match.range(at: 4), in: cleanNoComma) {
                let num = String(cleanNoComma[numRange])
                let code = String(cleanNoComma[codeRange]).lowercased()
                currency = currencySymbols[code]
                amount = Double(num)
            }
            // Pattern 3: bare number — inherit the detected currency
            else if match.range(at: 5).location != NSNotFound,
                    let numRange = Range(match.range(at: 5), in: cleanNoComma) {
                let num = String(cleanNoComma[numRange])
                amount = Double(num)
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
        let parts = lower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }

        let keyword = parts[0]
        // Strip currency symbols before parsing numbers
        let numbers = parts.dropFirst()
            .map { $0.replacingOccurrences(of: #"[\$€£¥₪]"#, with: "", options: .regularExpression) }
            .compactMap { Double($0) }
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
            let nums = filtered.compactMap { Double($0) }
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

    private static func evaluateUnitConversion(_ input: String) -> (expression: String, result: String)? {
        let lower = input.lowercased()

        // Pattern: "<number><unit> to/in <unit>" (space between number and unit is optional)
        let pattern = #"^([\d.,]+)\s*(.+?)\s+(?:to|in|as)\s+(.+)$"#
        guard let match = lower.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        let matched = String(lower[match])
        let regex = try! NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(matched.startIndex..., in: matched)
        guard let result = regex.firstMatch(in: matched, range: nsRange) else { return nil }

        let numStr = String(matched[Range(result.range(at: 1), in: matched)!]).replacingOccurrences(of: ",", with: "")
        let fromUnit = String(matched[Range(result.range(at: 2), in: matched)!]).trimmingCharacters(in: .whitespaces)
        let toUnit = String(matched[Range(result.range(at: 3), in: matched)!]).trimmingCharacters(in: .whitespaces)

        guard let value = Double(numStr) else { return nil }

        if let converted = convert(value, from: fromUnit, to: toUnit) {
            return (expression: input, result: "\(format(converted)) \(toUnit)")
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
            "acre": "acre", "acres": "acre",
            "hectare": "hectare", "hectares": "hectare",
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

        guard let value = Double(numStr),
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

            guard let value = Double(numStr),
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

        guard let value = Double(numStr) else { return nil }

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

    // MARK: - Standard Math Expression

    private static func evaluateExpression(_ input: String) -> (expression: String, result: String)? {
        // Pre-process
        var expr = input
        // Strip stray currency symbols that aren't part of a valid currency pattern
        expr = expr.replacingOccurrences(of: #"[\$€£¥₪]"#, with: "", options: .regularExpression)
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
        // x/X as multiplication: between numbers, after ), before (
        expr = expr.replacingOccurrences(
            of: #"([\d)])\s*[xX]\s*([\d(])"#,
            with: "$1*$2",
            options: .regularExpression
        )
        expr = expr.replacingOccurrences(of: "^", with: "**")

        let mathChars = CharacterSet(charactersIn: "+-*/%()")
        let mathFunctions = ["sqrt", "log", "ln", "abs", "ceil", "floor"]
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
        return (expression: input, result: formatted)
    }

    // MARK: - Formatting

    private static func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return formatter.string(from: NSNumber(value: Int(value))) ?? String(Int(value))
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
