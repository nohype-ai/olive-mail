import Foundation

extension HimalayaBackend {
    func showEmail(mailbox: String, id: String) async throws -> Email.View {
        let data = try await invoke(["message", "read", "-m", mailbox, id])
        return try parseMessage(data, mailbox: mailbox, id: id)
    }
}

private func parseMessage(_ data: Data, mailbox: String, id: String) throws -> Email.View {
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw OliveMailError.himalayaJSON(error.localizedDescription)
    }
    if let string = object as? String {
        return parseHuman(string, mailbox: mailbox, id: id)
    }
    guard let root = object as? [String: Any] else {
        throw OliveMailError.himalayaJSON("expected object")
    }
    if let error = root["error"] as? String {
        throw OliveMailError.himalayaFailed(error)
    }
    let parts = root["parts"] as? [[String: Any]] ?? []
    var from = ""
    var to = ""
    var date = ""
    var subject = ""
    if let headers = parts.first?["headers"] as? [[String: Any]] {
        for header in headers {
            switch (header["name"] as? String)?.lowercased() {
            case "from": from = formatHeaderAddress(header["value"])
            case "to": to = formatHeaderAddress(header["value"])
            case "subject": subject = headerText(header["value"])
            case "date": date = headerDate(header["value"])
            default: break
            }
        }
    }
    return Email.View(
        mailbox: mailbox,
        id: id,
        from: from,
        to: to,
        date: date,
        subject: subject,
        body: extractBody(root: root, parts: parts)
    )
}

private func extractBody(root: [String: Any], parts: [[String: Any]]) -> String {
    func body(at index: Int) -> String? {
        guard parts.indices.contains(index) else { return nil }
        let text = partText(parts[index])
        return text.isEmpty ? nil : text
    }
    if let indexes = intArray(root["text_body"]) {
        for index in indexes {
            if let text = body(at: index) { return text }
        }
    }
    if let indexes = intArray(root["html_body"]) {
        for index in indexes {
            if let text = body(at: index) { return text }
        }
    }
    for part in parts {
        let text = partText(part)
        if !text.isEmpty { return text }
    }
    return ""
}

private func partText(_ part: [String: Any]) -> String {
    guard let body = part["body"] as? [String: Any] else { return "" }
    if let text = body["Text"] as? String { return text }
    if let html = body["Html"] as? String { return html }
    return ""
}

private func formatHeaderAddress(_ value: Any?) -> String {
    guard let value = value as? [String: Any],
          let address = value["Address"] as? [String: Any] else {
        return headerText(value)
    }
    let list: [[String: Any]]
    if let items = address["List"] as? [[String: Any]] {
        list = items
    } else if let groups = address["Group"] as? [[String: Any]] {
        list = groups.flatMap { $0["addresses"] as? [[String: Any]] ?? [] }
    } else {
        return headerText(value)
    }
    return list.map { item in
        let email = item["address"] as? String ?? item["email"] as? String ?? ""
        return formatAddress(item["name"] as? String, email: email)
    }.joined(separator: ", ")
}

private func headerText(_ value: Any?) -> String {
    if let text = value as? String { return text }
    if let object = value as? [String: Any], let text = object["Text"] as? String {
        return text
    }
    return ""
}

private func headerDate(_ value: Any?) -> String {
    let text = headerText(value)
    if !text.isEmpty { return text }
    guard let object = value as? [String: Any],
          let dt = object["DateTime"] as? [String: Any],
          let year = intValue(dt["year"]),
          let month = intValue(dt["month"]),
          let day = intValue(dt["day"]) else {
        return ""
    }
    let hour = intValue(dt["hour"]) ?? 0
    let minute = intValue(dt["minute"]) ?? 0
    let second = intValue(dt["second"]) ?? 0
    return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", year, month, day, hour, minute, second)
}

private func parseHuman(_ text: String, mailbox: String, id: String) -> Email.View {
    var from = ""
    var to = ""
    var date = ""
    var subject = ""
    var bodyLines: [String] = []
    var inBody = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
        if !inBody {
            if line.hasPrefix("From: ") { from = String(line.dropFirst(6)) }
            else if line.hasPrefix("To: ") { to = String(line.dropFirst(4)) }
            else if line.hasPrefix("Date: ") { date = String(line.dropFirst(6)) }
            else if line.hasPrefix("Subject: ") { subject = String(line.dropFirst(9)) }
            else if line.isEmpty { inBody = true }
        } else {
            bodyLines.append(line)
        }
    }
    return Email.View(
        mailbox: mailbox,
        id: id,
        from: from,
        to: to,
        date: date,
        subject: subject,
        body: bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

private func intArray(_ value: Any?) -> [Int]? {
    if let ints = value as? [Int] { return ints }
    if let numbers = value as? [NSNumber] { return numbers.map(\.intValue) }
    return nil
}

private func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let number = value as? NSNumber { return number.intValue }
    return nil
}
