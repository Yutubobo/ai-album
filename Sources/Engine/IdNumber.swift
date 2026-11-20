import Foundation

/// 18 位居民身份证号码的校验与抽取。
///
/// 国标 GB 11643 的最后一位是按前 17 位加权取模得到的校验码。OCR 经常把某一位认错，
/// 校验一次就能把"真的身份证号"从一堆 18 位数字里挑出来；校验不过的号码仍然留在
/// 全文里，靠 bigram 检索兼底，所以不会丢结果。
enum IdNumber {

    private static let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
    private static let checkCodes = Array("10X98765432")

    static func isValid(_ candidate: String) -> Bool {
        let characters = Array(candidate.uppercased())
        guard characters.count == 18 else { return false }
        var sum = 0
        for index in 0..<17 {
            guard let digit = characters[index].wholeNumberValue, (0...9).contains(digit) else {
                return false
            }
            sum += digit * weights[index]
        }
        let expected = checkCodes[sum % 11]
        return characters[17] == expected
    }

    /// 从已归一化的文本里扫描所有连续 18 位、且校验通过的身份证号。
    static func extract(from normalizedText: String) -> [String] {
        var found = [String]()
        let characters = Array(normalizedText.uppercased())
        var index = 0
        while index < characters.count {
            guard characters[index].wholeNumberValue != nil,
                  let first = characters[index].wholeNumberValue, (0...9).contains(first) else {
                index += 1
                continue
            }
            var length = 0
            while index + length < characters.count {
                let character = characters[index + length]
                guard let value = character.wholeNumberValue, (0...9).contains(value) else { break }
                length += 1
            }
            // 身份证号必须是恰好 18 位连续数字（末位可能是 X，单独再判断）。
            if length >= 17 && length <= 18 {
                let tailIndex = index + 17
                let head = String(characters[index..<(index + 17)])
                var candidate = head
                if tailIndex < characters.count, characters[tailIndex] == "X" {
                    candidate.append("X")
                } else if length == 18 {
                    candidate.append(characters[index + 17])
                }
                if candidate.count == 18, isValid(candidate), !found.contains(candidate) {
                    found.append(candidate)
                }
            }
            index += max(length, 1)
        }
        return found
    }
}
