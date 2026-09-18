#!/usr/bin/env python3
"""
Dựng `lexicon.txt` cho bộ tách từ + pinyin của app (ChinesePinyin.swift).

Nguồn dữ liệu (tự tải về Tools/.cache/ nếu chưa có):
  - jieba dict.txt (MIT, https://github.com/fxsjy/jieba): tần suất và từ loại, dùng để chọn
    cách tách từ có xác suất cao nhất.
  - CC-CEDICT (CC BY-SA 4.0, https://www.mdbg.net/chinese/dictionary?page=cc-cedict):
    pinyin của từ.

Chỉ giữ từ có trong cả hai nguồn (lọc được "từ" rác của jieba như 我会, 你家) và chữ Hán
đơn lẻ có trong jieba (chỉ lấy tần suất, pinyin chữ đơn vẫn do app quyết định).

Dòng đầu "#total<TAB>tổng tần suất", sau đó mỗi dòng (UTF-8, tách bằng tab):
    từ <TAB> tần suất <TAB> từ loại jieba <TAB> pinyin có dấu, cách nhau bằng dấu cách
Chữ đơn để trống cột pinyin.

Cách chạy:
    python3 Tools/build_lexicon.py
"""

import gzip
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "Tools", ".cache")
OUTPUT = os.path.join(ROOT, "Ban Phim Tieng Trung", "lexicon.txt")

JIEBA_URL = "https://raw.githubusercontent.com/fxsjy/jieba/master/jieba/dict.txt"
CEDICT_URL = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"

# Từ nhiều chữ hiếm hơn ngưỡng này bị bỏ để file gọn (bàn phím bị iOS giới hạn bộ nhớ).
MIN_WORD_FREQ = 5
MAX_WORD_LEN = 6

# Cách đọc CC-CEDICT không hợp văn nói (穿着 chuānzhuó "trang phục" → chuānzhe "đang mặc").
OVERRIDES = {
    "穿着": "chuān zhe",
    "带上": "dài shang",
    "可不是": "kě bu shì",
}

HAN = re.compile(r"^[一-鿿㐀-䶿]+$")
CEDICT_LINE = re.compile(r"^(\S+) (\S+) \[([^\]]+)\] /(.*)/\s*$")
# Mục chỉ là biến thể / dùng trong từ khác / cách đọc Đài Loan: không dùng để chọn pinyin.
WEAK_SENSE = re.compile(r"^(old |unofficial |archaic )?variant of|^used in|^Taiwan pr\.|^see |^\(archaic\)|^surname ")

TONE_MARKS = {
    "a": "āáǎà", "e": "ēéěè", "i": "īíǐì", "o": "ōóǒò", "u": "ūúǔù", "ü": "ǖǘǚǜ",
}


def download(url, path):
    if os.path.exists(path):
        return
    os.makedirs(CACHE, exist_ok=True)
    print(f"Tải {url}")
    urllib.request.urlretrieve(url, path)


def numbered_to_marked(syllable):
    """hao3 → hǎo, nu:3 → nǚ, de5 → de, r5 → ér (儿 hoá, app tự gộp thành -r)."""
    s = syllable.lower().replace("u:", "ü").replace("v", "ü")
    if s == "r5":
        return "ér"
    tone = 5
    if s and s[-1].isdigit():
        tone = int(s[-1])
        s = s[:-1]
    if not re.fullmatch(r"[a-zü]+", s):
        return None
    if tone in (5, 0):
        return s
    # a/e luôn mang dấu; "ou" dấu trên o; còn lại dấu trên nguyên âm cuối.
    if "a" in s:
        index = s.index("a")
    elif "e" in s:
        index = s.index("e")
    elif "ou" in s:
        index = s.index("o")
    else:
        vowels = [i for i, c in enumerate(s) if c in "aeiouü"]
        if not vowels:  # m2, ng2, hm...
            return None
        index = vowels[-1]
    vowel = s[index]
    return s[:index] + TONE_MARKS[vowel][tone - 1] + s[index + 1:]


def load_cedict(path):
    """giản thể → pinyin có dấu, chọn mục có nhiều nghĩa thật nhất."""
    candidates = {}
    with gzip.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            if line.startswith("#"):
                continue
            m = CEDICT_LINE.match(line)
            if not m:
                continue
            simplified, pinyin, senses = m.group(2), m.group(3), m.group(4).split("/")
            if len(simplified) < 2 or not HAN.match(simplified):
                continue
            syllables = pinyin.split()
            if len(syllables) != len(simplified):
                continue
            # Tên riêng (pinyin viết hoa, như 北京 Bei3 jing1) chỉ dùng khi không có mục viết thường.
            proper = syllables[0][:1].isupper()
            marked = [numbered_to_marked(s) for s in syllables]
            if None in marked:
                continue
            strong = sum(1 for s in senses if s and not WEAK_SENSE.search(s))
            if strong == 0:
                continue
            candidates.setdefault(simplified, []).append((not proper, strong, " ".join(marked)))
    # Ưu tiên mục viết thường, rồi mục nhiều nghĩa hơn (东西 dōngxi > dōngxī); hoà thì giữ mục trước.
    return {w: max(c, key=lambda item: item[:2])[2] for w, c in candidates.items()}


def main():
    jieba_path = os.path.join(CACHE, "jieba-dict.txt")
    cedict_path = os.path.join(CACHE, "cedict_1_0_ts_utf-8_mdbg.txt.gz")
    download(JIEBA_URL, jieba_path)
    download(CEDICT_URL, cedict_path)

    cedict = load_cedict(cedict_path)

    rows = []
    with open(jieba_path, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) != 3:
                continue
            word, freq, pos = parts[0], int(parts[1]), parts[2]
            if not HAN.match(word) or len(word) > MAX_WORD_LEN:
                continue
            if len(word) == 1:
                rows.append((word, freq, pos, ""))
            elif freq >= MIN_WORD_FREQ and word in cedict:
                pinyin = OVERRIDES.get(word, cedict[word])
                # Phương vị từ 里 sau danh từ đọc nhẹ: 家里 jiāli, 心里 xīnli (trừ 这里, 哪里…).
                if len(word) == 2 and word.endswith("里") and pos in ("s", "f", "n") and pinyin.endswith("lǐ"):
                    pinyin = pinyin[:-2] + "li"
                rows.append((word, freq, pos, pinyin))

    rows.sort(key=lambda r: (-r[1], r[0]))
    with open(OUTPUT, "w", encoding="utf-8") as out:
        # Tổng tần suất để app tính xác suất mà không phải cộng lại khi nạp.
        out.write(f"#total\t{sum(r[1] for r in rows)}\n")
        for word, freq, pos, pinyin in rows:
            out.write(f"{word}\t{freq}\t{pos}\t{pinyin}\n")

    size = os.path.getsize(OUTPUT)
    print(f"Đã ghi {len(rows)} mục ({size / 1024:.0f} KB) vào {os.path.relpath(OUTPUT, ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
