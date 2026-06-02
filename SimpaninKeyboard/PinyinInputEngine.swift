import Foundation

struct PinyinInputEngine {
    struct Candidate: Identifiable, Equatable {
        let text: String
        let consumeLength: Int

        var id: String { "\(text)\t\(consumeLength)" }
    }

    private struct SelectedSegment {
        let pinyin: String
        let text: String
        let recordsSelection: Bool
    }

    private let candidateProvider = PinyinCandidateProvider()
    private let associationProvider = PinyinAssociationProvider()
    private var selectedSegments: [SelectedSegment] = []
    private var compositionBuffer = ""
    private var compositionCursorOffset = 0
    private var associationContext: String?

    var rawPinyin: String { selectedSegments.map(\.pinyin).joined() + compositionBuffer }
    var displayText: String { selectedSegments.map(\.text).joined() + compositionBuffer }
    var hasComposition: Bool { !selectedSegments.isEmpty || !compositionBuffer.isEmpty }
    var displayCursorOffset: Int { selectedSegments.map(\.text).joined().count + compositionCursorOffset }

    var candidates: [Candidate] {
        let candidateInput = String(compositionBuffer.prefix(compositionCursorOffset))
        if !candidateInput.isEmpty {
            return candidateProvider.candidates(for: candidateInput).map {
                Candidate(text: $0.text, consumeLength: $0.consumeLength)
            }
        }
        if selectedSegments.isEmpty, let associationContext {
            return associationProvider.associations(for: associationContext).map {
                Candidate(text: $0, consumeLength: 0)
            }
        }
        return []
    }

    mutating func insertLetter(_ letter: String) {
        guard !letter.isEmpty else { return }
        associationContext = nil
        let index = compositionBuffer.index(compositionBuffer.startIndex, offsetBy: compositionCursorOffset)
        compositionBuffer.insert(contentsOf: letter, at: index)
        compositionCursorOffset += letter.count
    }

    mutating func deleteBackward() -> Bool {
        if compositionCursorOffset > 0 {
            let removeEnd = compositionBuffer.index(compositionBuffer.startIndex, offsetBy: compositionCursorOffset)
            let removeStart = compositionBuffer.index(before: removeEnd)
            compositionBuffer.removeSubrange(removeStart..<removeEnd)
            compositionCursorOffset -= 1
            return true
        }
        if let segment = selectedSegments.popLast() {
            compositionBuffer = segment.pinyin
            compositionCursorOffset = compositionBuffer.count
            return true
        }
        associationContext = nil
        return false
    }

    mutating func clearComposition() {
        selectedSegments.removeAll()
        compositionBuffer = ""
        compositionCursorOffset = 0
    }

    mutating func setDisplayCursorOffset(_ offset: Int) {
        let selectedTextLength = selectedSegments.map(\.text).joined().count
        let editableOffset = max(0, min(offset - selectedTextLength, compositionBuffer.count))
        guard compositionCursorOffset != editableOffset else { return }
        compositionCursorOffset = editableOffset
    }

    mutating func select(_ candidate: Candidate) -> String? {
        guard hasComposition else {
            associationContext = limitedAssociationContext((associationContext ?? "") + candidate.text)
            return candidate.text
        }

        let candidateInputLength = compositionCursorOffset
        let consumeLength = candidate.consumeLength > 0 ? candidate.consumeLength : candidateInputLength
        let prefixLength = max(0, min(consumeLength, candidateInputLength, compositionBuffer.count))
        let end = compositionBuffer.index(compositionBuffer.startIndex, offsetBy: prefixLength)
        let consumedPinyin = String(compositionBuffer[..<end])
        compositionBuffer.removeSubrange(compositionBuffer.startIndex..<end)
        compositionCursorOffset = max(0, compositionCursorOffset - prefixLength)
        selectedSegments.append(SelectedSegment(
            pinyin: consumedPinyin,
            text: candidate.text,
            recordsSelection: candidate.consumeLength > 0
        ))

        if compositionBuffer.isEmpty {
            return commitCompositionAsText()
        }
        return nil
    }

    mutating func commitCompositionAsText() -> String? {
        guard hasComposition else { return nil }
        let text = displayText
        if compositionBuffer.isEmpty,
           selectedSegments.count > 1,
           selectedSegments.allSatisfy(\.recordsSelection) {
            let committedPinyin = selectedSegments.map(\.pinyin).joined()
            candidateProvider.recordSelection(text, for: committedPinyin)
        }
        associationContext = limitedAssociationContext(text)
        clearComposition()
        return text
    }

    private func limitedAssociationContext(_ text: String) -> String {
        let maxContextLength = 16
        guard text.count > maxContextLength else { return text }
        let start = text.index(text.endIndex, offsetBy: -maxContextLength)
        return String(text[start...])
    }
}
private struct PinyinCandidate {
    let text: String
    let weight: Int
    let tier: Int
    let wordLength: Int
    let syllableCount: Int
    let consumeLength: Int

    init(text: String, weight: Int, tier: Int = 2, wordLength: Int? = nil, syllableCount: Int = 1, consumeLength: Int = 0) {
        self.text = text
        self.weight = weight
        self.tier = tier
        self.wordLength = wordLength ?? text.count
        self.syllableCount = syllableCount
        self.consumeLength = consumeLength
    }
}

private struct PinyinCompletion {
    let key: String
    let consumeLength: Int
}

private struct PinyinCorrection {
    let key: String
    let syllables: [String]
    let cost: Int
    let correctedSyllables: Int
}

private struct PinyinSegmenter {
    private struct InitialShorthandChunk {
        let key: String
        let isShorthand: Bool
    }

    private struct CorrectionPath {
        let key: String
        let syllables: [String]
        let cost: Int
        let correctedSyllables: Int
        let sortScore: Int
    }

    private static let syllables: Set<String> = [
        "a", "ai", "an", "ang", "ao",
        "ba", "bai", "ban", "bang", "bao", "bei", "ben", "beng", "bi", "bian", "biao", "bie", "bin", "bing", "bo", "bu",
        "ca", "cai", "can", "cang", "cao", "ce", "cen", "ceng", "cha", "chai", "chan", "chang", "chao", "che", "chen", "cheng", "chi", "chong", "chou", "chu", "chua", "chuai", "chuan", "chuang", "chui", "chun", "chuo", "ci", "cong", "cou", "cu", "cuan", "cui", "cun", "cuo",
        "da", "dai", "dan", "dang", "dao", "de", "dei", "den", "deng", "di", "dia", "dian", "diao", "die", "ding", "diu", "dong", "dou", "du", "duan", "dui", "dun", "duo",
        "e", "ei", "en", "eng", "er",
        "fa", "fan", "fang", "fei", "fen", "feng", "fo", "fou", "fu",
        "ga", "gai", "gan", "gang", "gao", "ge", "gei", "gen", "geng", "gong", "gou", "gu", "gua", "guai", "guan", "guang", "gui", "gun", "guo",
        "ha", "hai", "han", "hang", "hao", "he", "hei", "hen", "heng", "hong", "hou", "hu", "hua", "huai", "huan", "huang", "hui", "hun", "huo",
        "ji", "jia", "jian", "jiang", "jiao", "jie", "jin", "jing", "jiong", "jiu", "ju", "juan", "jue", "jun",
        "ka", "kai", "kan", "kang", "kao", "ke", "ken", "keng", "kong", "kou", "ku", "kua", "kuai", "kuan", "kuang", "kui", "kun", "kuo",
        "la", "lai", "lan", "lang", "lao", "le", "lei", "leng", "li", "lia", "lian", "liang", "liao", "lie", "lin", "ling", "liu", "lo", "long", "lou", "lu", "lv", "luan", "lve", "lun", "luo",
        "ma", "mai", "man", "mang", "mao", "me", "mei", "men", "meng", "mi", "mian", "miao", "mie", "min", "ming", "miu", "mo", "mou", "mu",
        "na", "nai", "nan", "nang", "nao", "ne", "nei", "nen", "neng", "ni", "nian", "niang", "niao", "nie", "nin", "ning", "niu", "nong", "nou", "nu", "nv", "nuan", "nve", "nuo",
        "o", "ou",
        "pa", "pai", "pan", "pang", "pao", "pei", "pen", "peng", "pi", "pian", "piao", "pie", "pin", "ping", "po", "pou", "pu",
        "qi", "qia", "qian", "qiang", "qiao", "qie", "qin", "qing", "qiong", "qiu", "qu", "quan", "que", "qun",
        "ran", "rang", "rao", "re", "ren", "reng", "ri", "rong", "rou", "ru", "ruan", "rui", "run", "ruo",
        "sa", "sai", "san", "sang", "sao", "se", "sen", "seng", "sha", "shai", "shan", "shang", "shao", "she", "shen", "sheng", "shi", "shou", "shu", "shua", "shuai", "shuan", "shuang", "shui", "shun", "shuo", "si", "song", "sou", "su", "suan", "sui", "sun", "suo",
        "ta", "tai", "tan", "tang", "tao", "te", "teng", "ti", "tian", "tiao", "tie", "ting", "tong", "tou", "tu", "tuan", "tui", "tun", "tuo",
        "wa", "wai", "wan", "wang", "wei", "wen", "weng", "wo", "wu",
        "xi", "xia", "xian", "xiang", "xiao", "xie", "xin", "xing", "xiong", "xiu", "xu", "xuan", "xue", "xun",
        "ya", "yan", "yang", "yao", "ye", "yi", "yin", "ying", "yo", "yong", "you", "yu", "yuan", "yue", "yun",
        "za", "zai", "zan", "zang", "zao", "ze", "zei", "zen", "zeng", "zha", "zhai", "zhan", "zhang", "zhao", "zhe", "zhen", "zheng", "zhi", "zhong", "zhou", "zhu", "zhua", "zhuai", "zhuan", "zhuang", "zhui", "zhun", "zhuo", "zi", "zong", "zou", "zu", "zuan", "zui", "zun", "zuo"
    ]

    private static let completionPriority: [String: [String]] = [
        "h": ["hua", "huan", "han", "hao", "he", "hui", "huang", "hong", "huo", "hai", "hang", "heng", "hen", "ha", "hu"],
        "k": ["kan", "kao", "kai", "kuai", "ke", "kong", "kou", "ku", "kang", "ken", "keng", "ka", "kuan", "kuang", "kui", "kun", "kuo", "kua"],
        "s": ["shi", "shuo", "shang", "she", "shu", "shen", "sheng", "shou", "suo", "song", "si", "san", "sai", "su", "sa"],
        "x": ["xiang", "xin", "xing", "xian", "xiao", "xue", "xi", "xia", "xie", "xiu", "xu", "xuan", "xun", "xiong"]
    ]

    private static let orderedSyllables = syllables.sorted {
        if $0.count != $1.count {
            return $0.count < $1.count
        }
        return $0 < $1
    }
    private static let maxCorrectionCost = 2
    private static let maxCorrectedSyllables = 2
    private static let maxCorrectionInputLength = 18
    private static let maxCorrectionSpan = 7
    private static let maxCorrectionWidth = 24
    private static let keyboardNeighbors: [Character: String] = [
        "q": "wa", "w": "qase", "e": "wsdr", "r": "edft", "t": "rfgy", "y": "tghu", "u": "yhji", "i": "ujko", "o": "iklp", "p": "ol",
        "a": "qwsz", "s": "awedxz", "d": "serfcx", "f": "drtgvc", "g": "ftyhbv", "h": "gyujnb", "j": "huikmn", "k": "jiolm", "l": "kop",
        "z": "asx", "x": "zsdc", "c": "xdfv", "v": "cfgb", "b": "vghn", "n": "bhjm", "m": "njk"
    ]

    static func segment(_ key: String) -> [String] {
        var index = key.startIndex
        var result: [String] = []

        while index < key.endIndex {
            var best: String?
            var end = key.index(index, offsetBy: min(6, key.distance(from: index, to: key.endIndex)), limitedBy: key.endIndex) ?? key.endIndex
            while end > index {
                let piece = String(key[index..<end])
                if syllables.contains(piece) {
                    best = piece
                    break
                }
                end = key.index(before: end)
            }

            guard let best else { return [] }
            result.append(best)
            index = key.index(index, offsetBy: best.count)
        }

        return result
    }

    static func completionKeys(for key: String, limit: Int) -> [PinyinCompletion] {
        let partial = partialSegmentation(for: key)
        guard !partial.remainder.isEmpty, partial.remainder.count <= 3 else {
            return []
        }
        let chunks = prefixChunks(for: partial.remainder)
        guard !chunks.isEmpty else { return [] }

        let completions = chunks.map { completionSyllables(for: $0) }
        guard completions.allSatisfy({ !$0.isEmpty }) else { return [] }

        let baseKey = partial.segments.joined(separator: "")
        let baseConsumeLength = partial.segments.reduce(0) { $0 + $1.count }
        var results: [PinyinCompletion] = []
        var seen: Set<String> = []

        func append(_ key: String, consumedChunks: Int) {
            guard results.count < limit, key != baseKey, seen.insert(key).inserted else { return }
            let consumeLength = baseConsumeLength + chunks.prefix(consumedChunks).reduce(0) { $0 + $1.count }
            results.append(PinyinCompletion(key: key, consumeLength: consumeLength))
        }

        let primaryCompletion = completions.compactMap { $0.first }.joined(separator: "")
        append(baseKey + primaryCompletion, consumedChunks: completions.count)
        if completions.count > 1 {
            for count in stride(from: completions.count - 1, through: 1, by: -1) {
                let partialCompletion = completions.prefix(count).compactMap { $0.first }.joined(separator: "")
                append(baseKey + partialCompletion, consumedChunks: count)
            }
        }

        func build(index: Int, key: String) {
            guard results.count < limit else { return }
            if index == completions.count {
                append(key, consumedChunks: completions.count)
                return
            }

            for syllable in completions[index] {
                build(index: index + 1, key: key + syllable)
                if results.count >= limit {
                    break
                }
            }
        }

        build(index: 0, key: baseKey)
        return results
    }

    static func initialShorthandKeys(for key: String, limit: Int) -> [String] {
        guard limit > 0,
              let chunks = initialShorthandChunks(for: key),
              chunks.contains(where: \.isShorthand),
              chunks.contains(where: { !$0.isShorthand }) else {
            return []
        }

        let expansions = chunks.map { chunk in
            chunk.isShorthand ? completionSyllables(for: chunk.key) : [chunk.key]
        }
        guard expansions.allSatisfy({ !$0.isEmpty }) else { return [] }

        var results: [String] = []
        var seen: Set<String> = []

        func build(index: Int, key: String) {
            guard results.count < limit else { return }
            if index == expansions.count {
                guard key != "" && key != chunks.map(\.key).joined(separator: ""),
                      seen.insert(key).inserted else {
                    return
                }
                results.append(key)
                return
            }

            for syllable in expansions[index] {
                build(index: index + 1, key: key + syllable)
                if results.count >= limit {
                    break
                }
            }
        }

        build(index: 0, key: "")
        return results
    }

    static func acronymKeySequences(
        for key: String,
        syllablesPerLetterLimit: Int,
        sequenceLimit: Int
    ) -> [[String]] {
        guard key.count >= 2,
              key.count <= 6,
              syllablesPerLetterLimit > 0,
              sequenceLimit > 0,
              segment(key).joined(separator: "") != key else {
            return []
        }

        let letters = key.map { String($0) }
        guard letters.allSatisfy({ isInitialShorthand($0) }) else { return [] }

        let expansions = letters.map {
            Array(completionSyllables(for: $0).prefix(syllablesPerLetterLimit))
        }
        guard expansions.allSatisfy({ !$0.isEmpty }) else { return [] }

        var results: [[String]] = []

        func build(index: Int, sequence: [String]) {
            guard results.count < sequenceLimit else { return }
            if index == expansions.count {
                results.append(sequence)
                return
            }

            for syllable in expansions[index] {
                build(index: index + 1, sequence: sequence + [syllable])
                if results.count >= sequenceLimit {
                    break
                }
            }
        }

        build(index: 0, sequence: [])
        return results
    }

    static func correctionKeys(for key: String, limit: Int) -> [PinyinCorrection] {
        guard key.count >= 4, key.count <= maxCorrectionInputLength else { return [] }
        guard segment(key).joined(separator: "") != key else { return [] }

        let characters = Array(key)
        var paths = Array(repeating: [CorrectionPath](), count: characters.count + 1)
        paths[0] = [CorrectionPath(key: "", syllables: [], cost: 0, correctedSyllables: 0, sortScore: 0)]

        for start in 0..<characters.count {
            guard !paths[start].isEmpty else { continue }
            let maxEnd = min(characters.count, start + maxCorrectionSpan)

            for end in (start + 1)...maxEnd {
                let piece = String(characters[start..<end])
                let matches = correctionMatches(for: piece)
                guard !matches.isEmpty else { continue }

                for path in paths[start] {
                    for match in matches {
                        let correctedSyllables = path.correctedSyllables + (match.cost == 0 ? 0 : 1)
                        let cost = path.cost + match.cost
                        guard cost <= maxCorrectionCost,
                              correctedSyllables <= maxCorrectedSyllables else {
                            continue
                        }

                        paths[end].append(CorrectionPath(
                            key: path.key + match.syllable,
                            syllables: path.syllables + [match.syllable],
                            cost: cost,
                            correctedSyllables: correctedSyllables,
                            sortScore: path.sortScore + correctionSortRank(from: piece, to: match.syllable)
                        ))
                    }
                }

                paths[end] = pruneCorrectionPaths(paths[end])
            }
        }

        return pruneCorrectionPaths(paths[characters.count])
            .filter { $0.cost > 0 && $0.key != key }
            .prefix(limit)
            .map { path in
                PinyinCorrection(
                    key: path.key,
                    syllables: path.syllables,
                    cost: path.cost,
                    correctedSyllables: path.correctedSyllables
                )
            }
    }

    private static func partialSegmentation(for key: String) -> (segments: [String], remainder: String) {
        var index = key.startIndex
        var result: [String] = []

        while index < key.endIndex {
            var best: String?
            var end = key.index(index, offsetBy: min(6, key.distance(from: index, to: key.endIndex)), limitedBy: key.endIndex) ?? key.endIndex
            while end > index {
                let piece = String(key[index..<end])
                if syllables.contains(piece) {
                    best = piece
                    break
                }
                end = key.index(before: end)
            }

            guard let best else {
                return (result, String(key[index...]))
            }
            result.append(best)
            index = key.index(index, offsetBy: best.count)
        }

        return (result, "")
    }

    private static func initialShorthandChunks(for key: String) -> [InitialShorthandChunk]? {
        guard key.count >= 4 else { return nil }

        let indices = Array(key.indices) + [key.endIndex]
        var index = 0
        var result: [InitialShorthandChunk] = []

        while index < key.count {
            var best: String?
            let maxEnd = min(key.count, index + 6)
            for end in stride(from: maxEnd, through: index + 1, by: -1) {
                let piece = String(key[indices[index]..<indices[end]])
                if syllables.contains(piece) {
                    best = piece
                    break
                }
            }

            if let best {
                result.append(InitialShorthandChunk(key: best, isShorthand: false))
                index += best.count
                continue
            }

            let piece = String(key[indices[index]..<indices[index + 1]])
            guard isInitialShorthand(piece) else { return nil }
            result.append(InitialShorthandChunk(key: piece, isShorthand: true))
            index += 1
        }

        return result
    }

    private static func prefixChunks(for remainder: String) -> [String] {
        var chunks: [String] = []
        var index = remainder.startIndex

        while index < remainder.endIndex {
            var best: String?
            var end = remainder.index(index, offsetBy: min(4, remainder.distance(from: index, to: remainder.endIndex)), limitedBy: remainder.endIndex) ?? remainder.endIndex
            while end > index {
                let piece = String(remainder[index..<end])
                if hasSyllable(withPrefix: piece) {
                    best = piece
                    break
                }
                end = remainder.index(before: end)
            }

            guard let best else { return [] }
            chunks.append(best)
            index = remainder.index(index, offsetBy: best.count)
        }

        return chunks
    }

    private static func completionSyllables(for prefix: String) -> [String] {
        let matching = orderedSyllables.filter { $0.hasPrefix(prefix) }
        guard !matching.isEmpty else { return [] }

        let priority = completionPriority[prefix] ?? []
        let prioritySet = Set(priority)
        return priority.filter { syllables.contains($0) && $0.hasPrefix(prefix) }
            + matching.filter { !prioritySet.contains($0) }
    }

    private static func hasSyllable(withPrefix prefix: String) -> Bool {
        orderedSyllables.contains { $0.hasPrefix(prefix) }
    }

    private static func isInitialShorthand(_ key: String) -> Bool {
        key.count == 1 && !syllables.contains(key) && hasSyllable(withPrefix: key)
    }

    private static func correctionMatches(for piece: String) -> [(syllable: String, cost: Int)] {
        orderedSyllables.compactMap { syllable in
            correctionCost(from: piece, to: syllable).map { (syllable: syllable, cost: $0) }
        }
        .sorted {
            if $0.cost != $1.cost {
                return $0.cost < $1.cost
            }
            let firstPrefix = sharedPrefixLength($0.syllable, piece)
            let secondPrefix = sharedPrefixLength($1.syllable, piece)
            if firstPrefix != secondPrefix {
                return firstPrefix > secondPrefix
            }
            let firstRank = correctionSortRank(from: piece, to: $0.syllable)
            let secondRank = correctionSortRank(from: piece, to: $1.syllable)
            if firstRank != secondRank {
                return firstRank < secondRank
            }
            if $0.syllable.count != $1.syllable.count {
                return $0.syllable.count < $1.syllable.count
            }
            return $0.syllable < $1.syllable
        }
        .prefix(maxCorrectionWidth)
        .map { $0 }
    }

    private static func correctionCost(from input: String, to syllable: String) -> Int? {
        if input == syllable {
            return 0
        }

        let inputCharacters = Array(input)
        let syllableCharacters = Array(syllable)
        let lengthDelta = inputCharacters.count - syllableCharacters.count
        guard abs(lengthDelta) <= 1 else { return nil }

        if lengthDelta == 0 {
            if hasSingleAdjacentKeyboardSubstitution(inputCharacters, syllableCharacters)
                || hasAdjacentTransposition(inputCharacters, syllableCharacters) {
                return 1
            }
            return nil
        }

        let longer = lengthDelta > 0 ? inputCharacters : syllableCharacters
        let shorter = lengthDelta > 0 ? syllableCharacters : inputCharacters
        return canMatchBySkippingOneCharacter(longer: longer, shorter: shorter) ? 1 : nil
    }

    private static func correctionSortRank(from input: String, to syllable: String) -> Int {
        if input == syllable {
            return 0
        }

        let inputCharacters = Array(input)
        let syllableCharacters = Array(syllable)

        if inputCharacters.count == syllableCharacters.count {
            let mismatches = inputCharacters.indices.filter { inputCharacters[$0] != syllableCharacters[$0] }
            if mismatches.count == 1 {
                let typed = inputCharacters[mismatches[0]]
                let expected = syllableCharacters[mismatches[0]]
                if let neighbors = keyboardNeighbors[typed],
                   let index = neighbors.firstIndex(of: expected) {
                    return 10 + neighbors.distance(from: neighbors.startIndex, to: index)
                }
                if let neighbors = keyboardNeighbors[expected],
                   let index = neighbors.firstIndex(of: typed) {
                    return 10 + neighbors.distance(from: neighbors.startIndex, to: index)
                }
            }
            if mismatches.count == 2 {
                return 20
            }
        }

        return inputCharacters.count == syllableCharacters.count ? 30 : 14
    }

    private static func hasSingleAdjacentKeyboardSubstitution(_ input: [Character], _ syllable: [Character]) -> Bool {
        var mismatch: (Character, Character)?
        for index in input.indices {
            guard input[index] != syllable[index] else { continue }
            if mismatch != nil {
                return false
            }
            mismatch = (input[index], syllable[index])
        }

        guard let mismatch else { return false }
        return areKeyboardNeighbors(mismatch.0, mismatch.1)
    }

    private static func hasAdjacentTransposition(_ input: [Character], _ syllable: [Character]) -> Bool {
        var mismatches: [Int] = []
        for index in input.indices where input[index] != syllable[index] {
            mismatches.append(index)
        }

        guard mismatches.count == 2,
              mismatches[1] == mismatches[0] + 1 else {
            return false
        }

        return input[mismatches[0]] == syllable[mismatches[1]]
            && input[mismatches[1]] == syllable[mismatches[0]]
    }

    private static func canMatchBySkippingOneCharacter(longer: [Character], shorter: [Character]) -> Bool {
        var longerIndex = 0
        var shorterIndex = 0
        var skipped = false

        while longerIndex < longer.count && shorterIndex < shorter.count {
            if longer[longerIndex] == shorter[shorterIndex] {
                longerIndex += 1
                shorterIndex += 1
            } else if skipped {
                return false
            } else {
                skipped = true
                longerIndex += 1
            }
        }

        return true
    }

    private static func areKeyboardNeighbors(_ first: Character, _ second: Character) -> Bool {
        keyboardNeighbors[first]?.contains(second) == true
            || keyboardNeighbors[second]?.contains(first) == true
    }

    private static func sharedPrefixLength(_ first: String, _ second: String) -> Int {
        var length = 0
        for (left, right) in zip(first, second) {
            guard left == right else { break }
            length += 1
        }
        return length
    }

    private static func pruneCorrectionPaths(_ paths: [CorrectionPath]) -> [CorrectionPath] {
        var bestByKey: [String: CorrectionPath] = [:]
        for path in paths {
            if let current = bestByKey[path.key],
               current.cost < path.cost
                || (current.cost == path.cost && current.correctedSyllables < path.correctedSyllables)
                || (current.cost == path.cost
                    && current.correctedSyllables == path.correctedSyllables
                    && current.sortScore <= path.sortScore) {
                continue
            }
            bestByKey[path.key] = path
        }

        return bestByKey.values.sorted {
            if $0.cost != $1.cost {
                return $0.cost < $1.cost
            }
            if $0.key.count != $1.key.count {
                return $0.key.count < $1.key.count
            }
            if $0.sortScore != $1.sortScore {
                return $0.sortScore < $1.sortScore
            }
            if $0.correctedSyllables != $1.correctedSyllables {
                return $0.correctedSyllables < $1.correctedSyllables
            }
            if $0.syllables.count != $1.syllables.count {
                return $0.syllables.count < $1.syllables.count
            }
            return $0.key < $1.key
        }.prefix(maxCorrectionWidth).map { $0 }
    }
}

private final class PinyinAssociationProvider {
    private struct IndexRecord {
        let key: String
        let offset: UInt64
        let length: Int
    }

    private static let recordSize = 44
    private static let keySize = 32

    private let associationsURL = Bundle.main.url(forResource: "PinyinAssociations", withExtension: "tsv")
    private let indexURL = Bundle.main.url(forResource: "PinyinAssociations", withExtension: "idx")
    private let recordCount: Int

    init() {
        if let indexURL,
           let size = try? FileManager.default.attributesOfItem(atPath: indexURL.path)[.size] as? NSNumber {
            recordCount = size.intValue / Self.recordSize
        } else {
            recordCount = 0
        }
    }

    func associations(for context: String) -> [String] {
        let keys = lookupKeys(for: context)
        guard !keys.isEmpty else { return [] }

        var candidates: [PinyinCandidate] = []
        for (index, key) in keys.enumerated() {
            let baseWeight = 1_000_000 - index * 100_000
            candidates += weightedAssociations(for: key, baseWeight: baseWeight)
        }
        return merge(candidates).map(\.text)
    }

    private func lookupKeys(for context: String) -> [String] {
        let text = String(context.compactMap { character -> Character? in
            guard character.unicodeScalars.count == 1,
                  let scalar = character.unicodeScalars.first,
                  scalar.value >= 0x4e00,
                  scalar.value <= 0x9fff else {
                return nil
            }
            return character
        })
        guard text.count >= 2 else { return [] }

        let maxLength = min(4, text.count)
        return stride(from: maxLength, through: 2, by: -1).map { length in
            let start = text.index(text.endIndex, offsetBy: -length)
            return String(text[start...])
        }
    }

    private func weightedAssociations(for key: String, baseWeight: Int) -> [PinyinCandidate] {
        guard let lineCandidates = bundledAssociations(for: key) else { return [] }
        return lineCandidates.map { candidate in
            PinyinCandidate(text: candidate.text, weight: candidate.weight + baseWeight)
        }
    }

    private func bundledAssociations(for key: String) -> [PinyinCandidate]? {
        guard let associationsURL, let indexURL, recordCount > 0 else { return nil }
        guard let record = findRecord(for: key, in: indexURL) else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: associationsURL) else { return nil }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: record.offset)
            let data = try handle.read(upToCount: record.length) ?? Data()
            guard let line = String(data: data, encoding: .utf8) else { return nil }
            return line
                .trimmingCharacters(in: .newlines)
                .split(separator: "\t", omittingEmptySubsequences: true)
                .dropFirst()
                .enumerated()
                .map { index, field in
                    Self.parseCandidateField(String(field), fallbackWeight: 80 - index)
                }
        } catch {
            return nil
        }
    }

    private func findRecord(for key: String, in indexURL: URL) -> IndexRecord? {
        guard let handle = try? FileHandle(forReadingFrom: indexURL) else { return nil }
        defer { try? handle.close() }

        var low = 0
        var high = recordCount - 1

        while low <= high {
            let mid = (low + high) / 2
            guard let record = readRecord(at: mid, from: handle) else { return nil }
            let comparison = record.key.compare(key)

            if comparison == .orderedSame {
                return record
            } else if comparison == .orderedAscending {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return nil
    }

    private func readRecord(at index: Int, from handle: FileHandle) -> IndexRecord? {
        do {
            try handle.seek(toOffset: UInt64(index * Self.recordSize))
            let data = try handle.read(upToCount: Self.recordSize) ?? Data()
            guard data.count == Self.recordSize else { return nil }

            let keyData = data.prefix(Self.keySize).prefix { $0 != 0 }
            guard let key = String(data: Data(keyData), encoding: .utf8) else { return nil }

            let offset = Self.uint64LE(data, start: Self.keySize)
            let length = Int(Self.uint32LE(data, start: Self.keySize + 8))
            return IndexRecord(key: key, offset: offset, length: length)
        } catch {
            return nil
        }
    }

    private func merge(_ candidates: [PinyinCandidate]) -> [PinyinCandidate] {
        var bestByText: [String: PinyinCandidate] = [:]
        for candidate in candidates where !candidate.text.isEmpty {
            if let current = bestByText[candidate.text], current.weight >= candidate.weight {
                continue
            }
            bestByText[candidate.text] = candidate
        }
        return Array(bestByText.values)
            .sorted {
                if $0.weight != $1.weight {
                    return $0.weight > $1.weight
                }
                if $0.text.count != $1.text.count {
                    return $0.text.count < $1.text.count
                }
                return $0.text < $1.text
            }
    }

    private static func parseCandidateField(_ field: String, fallbackWeight: Int) -> PinyinCandidate {
        let parts = field.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 5 {
            let text = parts.dropLast(4).map(String.init).joined(separator: ":")
            let metadata = parts.suffix(4).map(String.init)
            return PinyinCandidate(
                text: text,
                weight: Int(metadata[0]) ?? fallbackWeight,
                tier: Int(metadata[1]) ?? 2,
                wordLength: Int(metadata[2]) ?? text.count,
                syllableCount: Int(metadata[3]) ?? 1
            )
        }

        guard let separator = field.lastIndex(of: ":") else {
            return PinyinCandidate(text: field, weight: fallbackWeight)
        }

        let text = String(field[..<separator])
        let weightText = String(field[field.index(after: separator)...])
        return PinyinCandidate(text: text, weight: Int(weightText) ?? fallbackWeight)
    }

    private static func uint64LE(_ data: Data, start: Int) -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<8 {
            result |= UInt64(data[start + index]) << UInt64(index * 8)
        }
        return result
    }

    private static func uint32LE(_ data: Data, start: Int) -> UInt32 {
        var result: UInt32 = 0
        for index in 0..<4 {
            result |= UInt32(data[start + index]) << UInt32(index * 8)
        }
        return result
    }
}

private final class PinyinCandidateProvider {
    private struct IndexRecord {
        let keyHash: UInt64
        let offset: UInt64
        let length: Int
    }

    private struct SelectionMemoryEntry {
        let count: Int
        let lastUsed: TimeInterval
    }

    private struct BeamPath {
        let text: String
        let score: Int
        let parts: Int
    }

    private struct LooseKeyAlias {
        let pinyinKeys: [String]
        let preferredText: String?
    }

    private enum MatchKind {
        case exact
        case completion
        case fuzzy
        case prefix
        case beam
        case fallback
    }

    private static let memoryDefaultsKey = "pinyinCandidateSelectionMemory.v2"
    private static let legacyMemoryDefaultsKey = "pinyinCandidateSelectionMemory.v1"
    private static let maxMemoryEntries = 1_000
    private static let maxMemoryCount = 100
    private static let memoryFrequencyStep = 160_000
    private static let maxMemoryBoost = 2_500_000
    private static let maxBundledCandidateCacheEntries = 512
    private static let recordSize = 20
    private static let fnvOffsetBasis: UInt64 = 14_695_981_039_346_656_037
    private static let fnvPrime: UInt64 = 1_099_511_628_211
    private static let maxBeamSyllables = 8
    private static let maxBeamSpan = 4
    private static let maxBeamWidth = 8
    private static let maxCompletionKeys = 32
    private static let completionRankPenalty = 120_000
    private static let initialShorthandPhraseBonus = 350_000
    private static let maxAcronymSyllablesPerLetter = 8
    private static let maxAcronymKeySequences = 512
    private static let maxAcronymFallbackSequences = 12
    private static let maxAcronymResults = 96
    private static let acronymPhraseBonus = 600_000
    private static let acronymFallbackBaseScore = 8_600_000
    private static let maxFuzzyCorrectionKeys = 24
    private static let fuzzyRankPenalty = 10_000
    private static let fuzzyCorrectionPenalty = 220_000
    private static let fuzzyDeletedCharacterBonus = 650_000
    private static let maxSegmentedPhraseInputLength = 18
    private static let maxSegmentedPhraseSpan = 6
    private static let maxSegmentedPhraseWidth = 10
    private static let looseKeyAliases: [String: [LooseKeyAlias]] = [
        "sj": [LooseKeyAlias(pinyinKeys: ["shouji"], preferredText: "手机")],
        "qwer": [LooseKeyAlias(pinyinKeys: ["chuqu", "waner"], preferredText: "出去玩儿")],
        "ty": [LooseKeyAlias(pinyinKeys: ["tianyu"], preferredText: "天宇")],
        "ii": [LooseKeyAlias(pinyinKeys: ["o"], preferredText: "哦")]
    ]

    private let lexiconURL = Bundle.main.url(forResource: "PinyinLexicon", withExtension: "tsv")
    private let indexURL = Bundle.main.url(forResource: "PinyinLexicon", withExtension: "idx")
    private let defaults = UserDefaults.standard
    private let bundledCandidateCacheLock = NSLock()
    private var bundledCandidateCache: [String: [PinyinCandidate]] = [:]
    private let recordCount: Int

    init() {
        if let indexURL,
           let size = try? FileManager.default.attributesOfItem(atPath: indexURL.path)[.size] as? NSNumber {
            recordCount = size.intValue / Self.recordSize
        } else {
            recordCount = 0
        }
    }

    func candidates(for pinyin: String) -> [PinyinCandidate] {
        let key = Self.normalizedKey(pinyin)
        guard !key.isEmpty else { return [] }

        var lookupCache: [String: [PinyinCandidate]] = [:]
        var candidates: [PinyinCandidate] = []
        let exactCandidates = scoredCandidates(for: key, match: .exact, consumeLength: key.count, cache: &lookupCache)
        candidates += exactCandidates
        let completionCandidates = completionCandidates(for: key, cache: &lookupCache)
        candidates += completionCandidates
        candidates += initialShorthandCandidates(for: key, cache: &lookupCache)
        candidates += acronymCandidates(for: key, cache: &lookupCache)
        if candidates.count < 16 {
            candidates += fuzzyCorrectionCandidates(for: key, cache: &lookupCache)
        }

        let segments = PinyinSegmenter.segment(key)
        if segments.count > 1 {
            candidates += beamCandidates(from: segments, fullKey: key, cache: &lookupCache)
        }

        if shouldUseSegmentedPhraseCandidates(
            for: key,
            segments: segments,
            hasExactCandidates: !exactCandidates.isEmpty,
            currentCandidateCount: candidates.count
        ) {
            candidates += segmentedPhraseCandidates(for: key, cache: &lookupCache)
        }

        if !completionCandidates.isEmpty || candidates.count < 16 {
            candidates += longestPrefixCandidates(for: key, cache: &lookupCache)
        }
        candidates += fallbackCandidates(for: key)

        return applyUserMemory(to: merge(candidates), key: key)
    }

    private func shouldUseSegmentedPhraseCandidates(
        for key: String,
        segments: [String],
        hasExactCandidates: Bool,
        currentCandidateCount: Int
    ) -> Bool {
        guard key.count >= 4, key.count <= Self.maxSegmentedPhraseInputLength else { return false }
        if segments.count > 1,
           segments.joined(separator: "") == key,
           (hasExactCandidates || currentCandidateCount >= 12) {
            return false
        }
        return true
    }

    func recordSelection(_ text: String, for pinyin: String) {
        let key = Self.normalizedKey(pinyin)
        guard !key.isEmpty, !text.isEmpty else { return }

        let memoryKey = Self.memoryKey(pinyin: key, text: text)
        var memory = selectionMemory
        let current = memory[memoryKey]
        let nextCount = min(Self.maxMemoryCount, (current?.count ?? 0) + 1)
        memory[memoryKey] = SelectionMemoryEntry(count: nextCount, lastUsed: Date().timeIntervalSince1970)

        if memory.count > Self.maxMemoryEntries {
            let sortedKeys = memory.sorted {
                if $0.value.count != $1.value.count {
                    return $0.value.count > $1.value.count
                }
                if $0.value.lastUsed != $1.value.lastUsed {
                    return $0.value.lastUsed > $1.value.lastUsed
                }
                return $0.key < $1.key
            }.prefix(Self.maxMemoryEntries).map(\.key)
            memory = Dictionary(uniqueKeysWithValues: sortedKeys.compactMap { key in
                memory[key].map { (key, $0) }
            })
        }

        let storage = memory.mapValues { entry in
            [
                "count": entry.count,
                "lastUsed": entry.lastUsed
            ] as [String: Any]
        }
        defaults.set(storage, forKey: Self.memoryDefaultsKey)
    }

    private func cachedBundledCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        if let cached = cache[key] {
            return cached
        }
        let candidates = bundledCandidates(for: key) ?? []
        cache[key] = candidates
        return candidates
    }

    private func scoredCandidates(
        for key: String,
        match: MatchKind,
        consumeLength: Int,
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        cachedBundledCandidates(for: key, cache: &cache).map { candidate in
            scoredCandidate(candidate, match: match, consumeLength: consumeLength)
        }
    }

    private func longestPrefixCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        var lookupKey = key
        while !lookupKey.isEmpty {
            lookupKey.removeLast()
            guard !lookupKey.isEmpty else { break }
            let candidates = scoredCandidates(for: lookupKey, match: .prefix, consumeLength: lookupKey.count, cache: &cache)
            if !candidates.isEmpty {
                return candidates
            }
        }
        return []
    }

    private func completionCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        PinyinSegmenter.completionKeys(for: key, limit: Self.maxCompletionKeys).enumerated().flatMap { rank, completion in
            scoredCandidates(for: completion.key, match: .completion, consumeLength: completion.consumeLength, cache: &cache).prefix(4).map { candidate in
                PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight - rank * Self.completionRankPenalty,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: candidate.consumeLength
                )
            }
        }
    }

    private func initialShorthandCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        PinyinSegmenter.initialShorthandKeys(for: key, limit: Self.maxCompletionKeys).flatMap { shorthandKey in
            scoredCandidates(for: shorthandKey, match: .completion, consumeLength: key.count, cache: &cache).prefix(4).map { candidate in
                PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight + Self.initialShorthandPhraseBonus,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: candidate.consumeLength
                )
            }
        }
    }

    private func acronymCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        let sequences = PinyinSegmenter.acronymKeySequences(
            for: key,
            syllablesPerLetterLimit: Self.maxAcronymSyllablesPerLetter,
            sequenceLimit: Self.maxAcronymKeySequences
        )
        guard !sequences.isEmpty else { return [] }

        var results: [PinyinCandidate] = []

        for sequence in sequences {
            let lookupKey = sequence.joined(separator: "")
            results += scoredCandidates(for: lookupKey, match: .completion, consumeLength: key.count, cache: &cache).prefix(3).map { candidate in
                PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight + Self.acronymPhraseBonus,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: candidate.consumeLength
                )
            }
            if results.count >= Self.maxAcronymResults {
                break
            }
        }

        for sequence in sequences.prefix(Self.maxAcronymFallbackSequences) {
            results += phraseCandidates(for: sequence, consumeLength: key.count, cache: &cache).prefix(2).map { candidate in
                PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight + Self.acronymFallbackBaseScore,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: candidate.consumeLength
                )
            }
        }

        return merge(results)
    }

    private func fuzzyCorrectionCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        PinyinSegmenter.correctionKeys(for: key, limit: Self.maxFuzzyCorrectionKeys).enumerated().flatMap { rank, correction in
            var results = scoredCandidates(for: correction.key, match: .fuzzy, consumeLength: key.count, cache: &cache).prefix(6).map { candidate in
                fuzzyCandidate(candidate, correction: correction, rank: rank, consumeLength: key.count)
            }

            if results.isEmpty {
                results += phraseCandidates(for: correction.syllables, consumeLength: key.count, cache: &cache).prefix(4).map { candidate in
                    fuzzyCandidate(candidate, correction: correction, rank: rank, consumeLength: key.count)
                }
            }

            return results
        }
    }

    private func beamCandidates(
        from segments: [String],
        fullKey: String,
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        guard segments.count > 1, segments.count <= Self.maxBeamSyllables else { return [] }

        var paths = Array(repeating: [BeamPath](), count: segments.count + 1)
        paths[0] = [BeamPath(text: "", score: 0, parts: 0)]

        for start in 0..<segments.count {
            guard !paths[start].isEmpty else { continue }
            let maxEnd = min(segments.count, start + Self.maxBeamSpan)
            for path in paths[start] {
                for end in (start + 1)...maxEnd {
                    let lookupKey = segments[start..<end].joined(separator: "")
                    guard lookupKey != fullKey else { continue }

                    let limit = end - start == 1 ? 4 : 8
                    let candidates = cachedBundledCandidates(for: lookupKey, cache: &cache).prefix(limit)
                    for candidate in candidates {
                        let text = path.text + candidate.text
                        guard text.count <= 16 else { continue }
                        let score = path.score + beamPartScore(candidate, span: end - start)
                        paths[end].append(BeamPath(text: text, score: score, parts: path.parts + 1))
                    }
                    paths[end] = pruneBeamPaths(paths[end])
                }
            }
        }

        return pruneBeamPaths(paths[segments.count])
            .filter { $0.parts > 1 }
            .map { path in
                let averageScore = path.score / max(1, path.parts)
                let score = 6_200_000 + averageScore - path.parts * 60_000
                return PinyinCandidate(
                    text: path.text,
                    weight: score,
                    tier: 2,
                    wordLength: path.text.count,
                    syllableCount: segments.count,
                    consumeLength: fullKey.count
                )
            }
    }

    private func pruneBeamPaths(_ paths: [BeamPath]) -> [BeamPath] {
        var bestByText: [String: BeamPath] = [:]
        for path in paths where !path.text.isEmpty || path.parts == 0 {
            if let current = bestByText[path.text], current.score >= path.score {
                continue
            }
            bestByText[path.text] = path
        }
        return bestByText.values.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            if $0.parts != $1.parts {
                return $0.parts < $1.parts
            }
            return $0.text < $1.text
        }.prefix(Self.maxBeamWidth).map { $0 }
    }

    private func segmentedPhraseCandidates(for key: String, cache: inout [String: [PinyinCandidate]]) -> [PinyinCandidate] {
        guard key.count >= 4, key.count <= Self.maxSegmentedPhraseInputLength else { return [] }

        let indices = Array(key.indices) + [key.endIndex]
        var paths = Array(repeating: [BeamPath](), count: key.count + 1)
        paths[0] = [BeamPath(text: "", score: 0, parts: 0)]

        for start in 0..<key.count {
            guard !paths[start].isEmpty else { continue }
            let matches = segmentedMatches(in: key, start: start, indices: indices, cache: &cache)
            guard !matches.isEmpty else { continue }

            for path in paths[start] {
                for match in matches {
                    let end = start + match.consumeLength
                    let text = path.text + match.text
                    guard text.count <= 24 else { continue }
                    let score = path.score + beamPartScore(match, span: max(1, match.syllableCount))
                    paths[end].append(BeamPath(text: text, score: score, parts: path.parts + 1))
                }
            }
            let maxEnd = min(key.count, start + Self.maxSegmentedPhraseSpan)
            for end in (start + 1)...maxEnd where !paths[end].isEmpty {
                paths[end] = pruneSegmentedPhrasePaths(paths[end])
            }
        }

        return pruneSegmentedPhrasePaths(paths[key.count])
            .filter { $0.parts > 1 }
            .map { path in
                let averageScore = path.score / max(1, path.parts)
                let score = 2_600_000 + averageScore - path.parts * 90_000
                return PinyinCandidate(
                    text: path.text,
                    weight: score,
                    tier: 4,
                    wordLength: path.text.count,
                    syllableCount: path.parts,
                    consumeLength: key.count
                )
            }
    }

    private func segmentedMatches(
        in key: String,
        start: Int,
        indices: [String.Index],
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        let maxEnd = min(key.count, start + Self.maxSegmentedPhraseSpan)
        guard maxEnd > start else { return [] }

        var results: [PinyinCandidate] = []
        for end in stride(from: maxEnd, through: start + 1, by: -1) {
            let piece = String(key[indices[start]..<indices[end]])
            let consumeLength = end - start

            let exact = scoredCandidates(for: piece, match: .exact, consumeLength: consumeLength, cache: &cache).prefix(4)
            results += exact

            let aliases = looseAliasCandidates(for: piece, consumeLength: consumeLength, cache: &cache).prefix(4)
            results += aliases

            let completions = segmentedCompletionCandidates(for: piece, consumeLength: consumeLength, cache: &cache).prefix(4)
            results += completions
        }

        return results.sorted {
            if $0.weight != $1.weight {
                return $0.weight > $1.weight
            }
            if $0.consumeLength != $1.consumeLength {
                return $0.consumeLength > $1.consumeLength
            }
            return $0.text < $1.text
        }.prefix(12).map { $0 }
    }

    private func looseAliasCandidates(
        for key: String,
        consumeLength: Int,
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        guard let aliases = Self.looseKeyAliases[key] else { return [] }
        var candidates: [PinyinCandidate] = []

        for (aliasIndex, alias) in aliases.enumerated() {
            if let preferredText = alias.preferredText {
                candidates.append(PinyinCandidate(
                    text: preferredText,
                    weight: 1_800_000 - aliasIndex * 10_000,
                    tier: 4,
                    wordLength: preferredText.count,
                    syllableCount: alias.pinyinKeys.count,
                    consumeLength: consumeLength
                ))
            }
            candidates += phraseCandidates(for: alias.pinyinKeys, consumeLength: consumeLength, cache: &cache)
        }

        return merge(candidates)
    }

    private func phraseCandidates(
        for pinyinKeys: [String],
        consumeLength: Int,
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        guard !pinyinKeys.isEmpty else { return [] }
        var paths = [BeamPath(text: "", score: 0, parts: 0)]

        for pinyinKey in pinyinKeys {
            let candidates = cachedBundledCandidates(for: pinyinKey, cache: &cache).prefix(3)
            guard !candidates.isEmpty else { return [] }

            var nextPaths: [BeamPath] = []
            for path in paths {
                for candidate in candidates {
                    let text = path.text + candidate.text
                    let score = path.score + beamPartScore(candidate, span: 1)
                    nextPaths.append(BeamPath(text: text, score: score, parts: path.parts + 1))
                }
            }
            paths = pruneSegmentedPhrasePaths(nextPaths)
        }

        return paths.map { path in
            PinyinCandidate(
                text: path.text,
                weight: path.score / max(1, path.parts),
                tier: 4,
                wordLength: path.text.count,
                syllableCount: pinyinKeys.count,
                consumeLength: consumeLength
            )
        }
    }

    private func segmentedCompletionCandidates(
        for key: String,
        consumeLength: Int,
        cache: inout [String: [PinyinCandidate]]
    ) -> [PinyinCandidate] {
        PinyinSegmenter.completionKeys(for: key, limit: 12).enumerated().flatMap { rank, completion in
            scoredCandidates(for: completion.key, match: .completion, consumeLength: consumeLength, cache: &cache).prefix(3).map { candidate in
                PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight - rank * Self.completionRankPenalty,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: consumeLength
                )
            }
        }
    }

    private func pruneSegmentedPhrasePaths(_ paths: [BeamPath]) -> [BeamPath] {
        var bestByText: [String: BeamPath] = [:]
        for path in paths where !path.text.isEmpty || path.parts == 0 {
            if let current = bestByText[path.text], current.score >= path.score {
                continue
            }
            bestByText[path.text] = path
        }
        return bestByText.values.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            if $0.parts != $1.parts {
                return $0.parts < $1.parts
            }
            return $0.text < $1.text
        }.prefix(Self.maxSegmentedPhraseWidth).map { $0 }
    }

    private func fallbackCandidates(for key: String) -> [PinyinCandidate] {
        var candidates: [PinyinCandidate] = []

        if let exact = Self.fallbackDictionary[key] {
            candidates += exact.enumerated().map { index, text in
                PinyinCandidate(text: text, weight: 1_000_000 + 10_000 - index, tier: 5, consumeLength: key.count)
            }
        }

        let prefixCandidates = Self.fallbackDictionary
            .filter { $0.key.hasPrefix(key) }
            .sorted { $0.key.count == $1.key.count ? $0.key < $1.key : $0.key.count < $1.key.count }
            .flatMap(\.value)

        candidates += prefixCandidates.enumerated().map { index, text in
            PinyinCandidate(text: text, weight: 900_000 - index, tier: 5, consumeLength: key.count)
        }

        return candidates
    }

    private func scoredCandidate(_ candidate: PinyinCandidate, match: MatchKind, consumeLength: Int) -> PinyinCandidate {
        let baseScore: Int
        let lengthBonus: Int
        switch match {
        case .exact:
            baseScore = 10_000_000
            lengthBonus = min(candidate.wordLength, 8) * 45_000
        case .completion:
            baseScore = 8_400_000
            lengthBonus = min(candidate.wordLength, 8) * 35_000
        case .fuzzy:
            baseScore = 8_000_000
            lengthBonus = min(candidate.wordLength, 8) * 35_000
        case .prefix:
            baseScore = 4_800_000
            lengthBonus = min(candidate.wordLength, 8) * 20_000
        case .beam:
            baseScore = 6_200_000
            lengthBonus = min(candidate.wordLength, 8) * 25_000
        case .fallback:
            baseScore = 900_000
            lengthBonus = 0
        }

        let score = baseScore
            + dictionaryScore(candidate.weight)
            + tierBonus(candidate.tier)
            + lengthBonus
            + min(candidate.syllableCount, 6) * 35_000

        return PinyinCandidate(
            text: candidate.text,
            weight: score,
            tier: candidate.tier,
            wordLength: candidate.wordLength,
            syllableCount: candidate.syllableCount,
            consumeLength: consumeLength
        )
    }

    private func fuzzyCandidate(
        _ candidate: PinyinCandidate,
        correction: PinyinCorrection,
        rank: Int,
        consumeLength: Int
    ) -> PinyinCandidate {
        PinyinCandidate(
            text: candidate.text,
            weight: candidate.weight
                - correction.cost * Self.fuzzyCorrectionPenalty
                - correction.correctedSyllables * 80_000
                - rank * Self.fuzzyRankPenalty
                + max(0, consumeLength - correction.key.count) * Self.fuzzyDeletedCharacterBonus,
            tier: candidate.tier,
            wordLength: candidate.wordLength,
            syllableCount: candidate.syllableCount,
            consumeLength: consumeLength
        )
    }

    private func beamPartScore(_ candidate: PinyinCandidate, span: Int) -> Int {
        let singleCharacterPenalty = span == 1 && candidate.wordLength == 1 ? 500_000 : 0
        return dictionaryScore(candidate.weight)
            + tierBonus(candidate.tier)
            + min(candidate.wordLength, 8) * 30_000
            + max(0, span - 1) * 350_000
            - singleCharacterPenalty
    }

    private func dictionaryScore(_ weight: Int) -> Int {
        min(max(weight, 1), 1_200_000)
    }

    private func tierBonus(_ tier: Int) -> Int {
        if tier <= 0 {
            return 600_000
        }
        switch tier {
        case 1:
            return 420_000
        case 2:
            return 260_000
        case 3:
            return 120_000
        case 4:
            return 40_000
        default:
            return 0
        }
    }

    private func merge(_ candidates: [PinyinCandidate]) -> [PinyinCandidate] {
        var bestByText: [String: PinyinCandidate] = [:]
        for candidate in candidates where !candidate.text.isEmpty {
            if let current = bestByText[candidate.text], current.weight >= candidate.weight {
                continue
            }
            bestByText[candidate.text] = candidate
        }
        return Array(bestByText.values)
            .sorted {
                if $0.weight != $1.weight {
                    return $0.weight > $1.weight
                }
                if $0.text.count != $1.text.count {
                    return $0.text.count < $1.text.count
                }
                return $0.text < $1.text
            }
    }

    private func applyUserMemory(to candidates: [PinyinCandidate], key: String) -> [PinyinCandidate] {
        let memory = selectionMemory
        let now = Date().timeIntervalSince1970
        return candidates
            .map { candidate in
                let entry = memory[Self.memoryKey(pinyin: key, text: candidate.text)]
                let boost = memoryBoost(for: entry, now: now)
                return PinyinCandidate(
                    text: candidate.text,
                    weight: candidate.weight + boost,
                    tier: candidate.tier,
                    wordLength: candidate.wordLength,
                    syllableCount: candidate.syllableCount,
                    consumeLength: candidate.consumeLength
                )
            }
            .sorted {
                if $0.weight != $1.weight {
                    return $0.weight > $1.weight
                }
                if $0.text.count != $1.text.count {
                    return $0.text.count < $1.text.count
                }
                return $0.text < $1.text
            }
    }

    private func memoryBoost(for entry: SelectionMemoryEntry?, now: TimeInterval) -> Int {
        guard let entry else { return 0 }

        let frequency = min(Self.maxMemoryCount, entry.count) * Self.memoryFrequencyStep
        let recency: Int
        if entry.lastUsed > 0 {
            let ageDays = max(0, (now - entry.lastUsed) / 86_400)
            recency = max(0, 350_000 - Int(ageDays * 20_000))
        } else {
            recency = 0
        }

        return min(Self.maxMemoryBoost, frequency + recency)
    }

    private var selectionMemory: [String: SelectionMemoryEntry] {
        if let rawMemory = defaults.dictionary(forKey: Self.memoryDefaultsKey) {
            return parseSelectionMemory(rawMemory)
        }
        guard let legacyMemory = defaults.dictionary(forKey: Self.legacyMemoryDefaultsKey) else { return [:] }
        return legacyMemory.compactMapValues { value in
            if let count = value as? Int {
                return SelectionMemoryEntry(count: count, lastUsed: 0)
            }
            if let count = value as? NSNumber {
                return SelectionMemoryEntry(count: count.intValue, lastUsed: 0)
            }
            return nil
        }
    }

    private func parseSelectionMemory(_ rawMemory: [String: Any]) -> [String: SelectionMemoryEntry] {
        return rawMemory.compactMapValues { value in
            if let entry = value as? [String: Any] {
                return Self.parseMemoryEntry(entry)
            }
            if let entry = value as? [String: NSNumber] {
                return SelectionMemoryEntry(
                    count: entry["count"]?.intValue ?? 0,
                    lastUsed: entry["lastUsed"]?.doubleValue ?? 0
                )
            }
            return nil
        }
    }

    private static func parseMemoryEntry(_ entry: [String: Any]) -> SelectionMemoryEntry {
        let count: Int
        if let value = entry["count"] as? Int {
            count = value
        } else if let value = entry["count"] as? NSNumber {
            count = value.intValue
        } else {
            count = 0
        }

        let lastUsed: TimeInterval
        if let value = entry["lastUsed"] as? TimeInterval {
            lastUsed = value
        } else if let value = entry["lastUsed"] as? NSNumber {
            lastUsed = value.doubleValue
        } else {
            lastUsed = 0
        }

        return SelectionMemoryEntry(count: count, lastUsed: lastUsed)
    }

    private static func memoryKey(pinyin: String, text: String) -> String {
        pinyin + "\t" + text
    }

    private func bundledCandidates(for key: String) -> [PinyinCandidate]? {
        if let cached = memoryCachedBundledCandidates(for: key) {
            return cached.isEmpty ? nil : cached
        }

        guard let lexiconURL, let indexURL, recordCount > 0 else { return nil }
        let records = findRecords(for: key, in: indexURL)
        guard !records.isEmpty else {
            storeBundledCandidates([], for: key)
            return nil
        }
        guard let handle = try? FileHandle(forReadingFrom: lexiconURL) else { return nil }
        defer { try? handle.close() }

        for record in records {
            do {
                try handle.seek(toOffset: record.offset)
                let data = try handle.read(upToCount: record.length) ?? Data()
                guard let line = String(data: data, encoding: .utf8) else { continue }
                let fields = line
                    .trimmingCharacters(in: .newlines)
                    .split(separator: "\t", omittingEmptySubsequences: true)
                guard fields.first.map(String.init) == key else { continue }
                let candidates = fields
                    .dropFirst()
                    .enumerated()
                    .map { index, field in
                        Self.parseCandidateField(String(field), fallbackWeight: 120 - index)
                    }
                storeBundledCandidates(candidates, for: key)
                return candidates
            } catch {
                continue
            }
        }

        storeBundledCandidates([], for: key)
        return nil
    }

    private func memoryCachedBundledCandidates(for key: String) -> [PinyinCandidate]? {
        bundledCandidateCacheLock.lock()
        defer { bundledCandidateCacheLock.unlock() }
        return bundledCandidateCache[key]
    }

    private func storeBundledCandidates(_ candidates: [PinyinCandidate], for key: String) {
        bundledCandidateCacheLock.lock()
        defer { bundledCandidateCacheLock.unlock() }
        if bundledCandidateCache[key] == nil,
           bundledCandidateCache.count >= Self.maxBundledCandidateCacheEntries {
            bundledCandidateCache.removeAll(keepingCapacity: true)
        }
        bundledCandidateCache[key] = candidates
    }

    private func findRecords(for key: String, in indexURL: URL) -> [IndexRecord] {
        guard let handle = try? FileHandle(forReadingFrom: indexURL) else { return [] }
        defer { try? handle.close() }

        let targetHash = Self.hashKey(key)
        var low = 0
        var high = recordCount

        while low < high {
            let mid = (low + high) / 2
            guard let record = readRecord(at: mid, from: handle) else { return [] }
            if record.keyHash < targetHash {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var results: [IndexRecord] = []
        var index = low
        while index < recordCount {
            guard let record = readRecord(at: index, from: handle), record.keyHash == targetHash else {
                break
            }
            results.append(record)
            index += 1
        }

        return results
    }

    private func readRecord(at index: Int, from handle: FileHandle) -> IndexRecord? {
        do {
            try handle.seek(toOffset: UInt64(index * Self.recordSize))
            let data = try handle.read(upToCount: Self.recordSize) ?? Data()
            guard data.count == Self.recordSize else { return nil }

            let keyHash = Self.uint64LE(data, start: 0)
            let offset = Self.uint64LE(data, start: 8)
            let length = Int(Self.uint32LE(data, start: 16))
            return IndexRecord(keyHash: keyHash, offset: offset, length: length)
        } catch {
            return nil
        }
    }

    private static func normalizedKey(_ value: String) -> String {
        String(value.lowercased().filter { character in
            guard character.unicodeScalars.count == 1,
                  let scalar = character.unicodeScalars.first else {
                return false
            }
            return scalar.value >= 97 && scalar.value <= 122
        })
    }

    private static func hashKey(_ key: String) -> UInt64 {
        var result = Self.fnvOffsetBasis
        for byte in key.utf8 {
            result ^= UInt64(byte)
            result = result &* Self.fnvPrime
        }
        return result
    }

    private static func parseCandidateField(_ field: String, fallbackWeight: Int) -> PinyinCandidate {
        let parts = field.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 5 {
            let text = parts.dropLast(4).map(String.init).joined(separator: ":")
            let metadata = parts.suffix(4).map(String.init)
            return PinyinCandidate(
                text: text,
                weight: Int(metadata[0]) ?? fallbackWeight,
                tier: Int(metadata[1]) ?? 2,
                wordLength: Int(metadata[2]) ?? text.count,
                syllableCount: Int(metadata[3]) ?? 1
            )
        }

        guard let separator = field.lastIndex(of: ":") else {
            return PinyinCandidate(text: field, weight: fallbackWeight)
        }

        let text = String(field[..<separator])
        let weightText = String(field[field.index(after: separator)...])
        return PinyinCandidate(text: text, weight: Int(weightText) ?? fallbackWeight)
    }

    private static func uint64LE(_ data: Data, start: Int) -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<8 {
            result |= UInt64(data[start + index]) << UInt64(index * 8)
        }
        return result
    }

    private static func uint32LE(_ data: Data, start: Int) -> UInt32 {
        var result: UInt32 = 0
        for index in 0..<4 {
            result |= UInt32(data[start + index]) << UInt32(index * 8)
        }
        return result
    }

    private static let fallbackDictionary: [String: [String]] = [
        "a": ["啊", "阿"],
        "ai": ["爱", "唉", "矮"],
        "an": ["按", "安", "安全"],
        "ang": ["昂"],
        "ba": ["把", "吧", "爸"],
        "bai": ["白", "百", "摆"],
        "ban": ["办", "半", "班"],
        "bao": ["包", "报", "宝"],
        "bei": ["被", "北", "杯", "北京"],
        "bu": ["不", "部", "步", "不错"],
        "cha": ["查", "差", "茶"],
        "chang": ["长", "常", "场"],
        "chi": ["吃", "持", "迟"],
        "da": ["大", "打", "达"],
        "de": ["的", "得", "地"],
        "di": ["第", "低", "地"],
        "dian": ["点", "电", "店"],
        "dui": ["对", "队"],
        "fa": ["发", "法"],
        "ge": ["个", "哥", "各"],
        "guo": ["过", "国", "果"],
        "hao": ["好", "号", "浩"],
        "he": ["和", "喝", "河"],
        "hen": ["很"],
        "hui": ["会", "回"],
        "jia": ["家", "加", "假"],
        "jian": ["见", "间", "件"],
        "jin": ["今", "进", "近"],
        "jiu": ["就", "九", "久"],
        "kan": ["看"],
        "ke": ["可", "课", "客"],
        "lai": ["来"],
        "le": ["了", "乐"],
        "li": ["里", "理", "力"],
        "ma": ["吗", "妈", "马"],
        "mei": ["没", "美", "每"],
        "men": ["们", "门"],
        "ming": ["明", "名"],
        "ni": ["你", "呢", "尼", "你好", "你们"],
        "nihao": ["你好"],
        "qing": ["请", "清"],
        "qu": ["去", "取"],
        "ren": ["人", "认"],
        "shang": ["上", "商"],
        "shen": ["什", "深", "身"],
        "shenme": ["什么"],
        "shi": ["是", "时", "事", "时间"],
        "shijian": ["时间"],
        "ta": ["他", "她", "它"],
        "tian": ["天", "田"],
        "wan": ["完", "晚", "玩"],
        "wei": ["为", "位", "微"],
        "wo": ["我", "我们"],
        "women": ["我们"],
        "xiang": ["想", "向", "像"],
        "xiao": ["小", "笑"],
        "xiexie": ["谢谢"],
        "yao": ["要"],
        "ye": ["也"],
        "yi": ["一", "以", "已"],
        "you": ["有", "又", "由"],
        "yu": ["于", "语"],
        "zai": ["在", "再"],
        "zao": ["早"],
        "zen": ["怎"],
        "zenme": ["怎么"],
        "zhe": ["这", "着"],
        "zhong": ["中", "种"]
    ]
}


