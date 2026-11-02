# frozen_string_literal: true

module Geo
  # Common distinctive character pairs provide a script hint, not a region guess.
  class Language
    PAIRS = %w[这這 为為 个個 来來 说說 时時 会會 对對 学學 国國 网網 页頁 资資 体體 简簡 术術 语語 话話 问問 题題
      关關 键鍵 词詞 数數 据據 选選 择擇 师師 荐薦 课課 费費 价價 钱錢 购購 买買 卖賣 产產 业業 务務 机機
      构構 发發 布佈 现現 实實 验驗 经經 济濟 统統 计計 设設 备備 应應 该該 与與 专專 长長 进進 达達 开開
      结結 组組 织織 过過 滤濾 仅僅 优優 权權 级級 别別 标標 签簽 转轉 换換 输輸 连連 线線 录錄 读讀 写寫
      证證 认認 识識 准準 确確 误誤 处處 软軟 负負 责責 动動 态態 变變 总總 览覽 见見 观觀 点點 东東 广廣
      台臺 湾灣 汉漢 门門 马馬 车車 云雲 电電 脑腦 书書 库庫 记記 忆憶 报報 艺藝 爱愛 欢歡 乐樂 练練 习習
      测測 试試 历歷 规規 范範 压壓 缩縮 势勢 获獲 听聽 声聲 办辦 导導 医醫 药藥 护護 养養 龄齡 鱼魚 龙龍
      齐齊 万萬 亿億 复復 杂雜 难難 轻輕 远遠 迁遷 针針 钟鐘 随隨 让讓 还還 没沒 无無 于於 从從 众眾 传傳
      伤傷 际際 队隊 协協 联聯 帐帳 账賬 户戶 隐隱 访訪 劝勸 议議 订訂 评評 内內 创創 场場 础礎 项項 类類
      请請 给給 带帶 间間 种種 样樣 够夠 义義 显顯 图圖 属屬 扩擴 绍紹 帮幫
      们們 么麼 寻尋 职職 两兩 气氣 后後 则則 虽雖 却卻 将將 区區 块塊 链鏈 码碼 硕碩
      约約 红紅 绿綠 蓝藍 黄黃 颜顏 边邊 细細 节節 维維 丝絲 绘繪 绝絕 纸紙 纯純 纳納
      终終 续續 绩績 兴興 趋趨 惯慣 劳勞 灵靈 头頭 笔筆 画畫 监監 视視 觉覺 厅廳 卫衛
      阶階 层層 县縣 乡鄉 礼禮 风風 飞飛 亲親 儿兒 里裏 里裡 制製 锐銳 谢謝 讲講 许許].freeze
    SHARED = %w[台 布 于 云 范 准 后 里 制].freeze
    SIMPLIFIED = Regexp.new("[#{(PAIRS.map { |pair| pair[0] } - SHARED).join}]").freeze
    TRADITIONAL = Regexp.new("[#{PAIRS.map { |pair| pair[1] }.join}]").freeze
    ENGLISH = %w[the a an and or of to for in on with is are was be this that these those it its
      you your we our can will how what which when where why from by as at not only use using
      should have has more than search guide official documentation data tools compare recommended].freeze
    LABELS = { "en" => "英文", "zh-Hans" => "简体中文", "zh-Hant" => "繁体中文", "zh" => "中文（字形未区分）",
               "ja" => "日文", "ko" => "韩文", "other" => "其他语言", "unknown" => "语言待确认" }.freeze

    def self.detect(text, question: false)
      text = text.to_s[0, 8000].gsub(%r{https?://\S+}, " ").gsub(/`[^`]*`/, " ")
      return "ja" if text.scan(/[\p{Hiragana}\p{Katakana}]/).length >= 3
      return "ko" if text.match?(/\p{Hangul}/)
      han = text.scan(/\p{Han}/).length
      words = text.downcase.scan(/[a-z]+/)
      english = (words.uniq & ENGLISH).length
      if han > 0 && !(english >= 4 && han * 3 < words.join.length)
        simple, traditional = text.scan(SIMPLIFIED).length, text.scan(TRADITIONAL).length
        return "zh-Hant" if traditional > simple
        return "zh-Hans" if simple > traditional || question
        return "zh"
      end
      return "en" if english >= 2 || (question && !words.empty?)
      text.match?(/[\p{L}]/) ? "other" : "unknown"
    end

    def self.assessment(text)
      text = text.to_s[0, 8000].gsub(%r{https?://\S+}, " ").gsub(/`[^`]*`/, " ")
      han, latin = text.scan(/\p{Han}/).length, text.scan(/[A-Za-z]/).length
      simple, traditional = text.scan(SIMPLIFIED).length, text.scan(TRADITIONAL).length
      english = (text.downcase.scan(/[a-z]+/).uniq & ENGLISH).length
      mixed = han >= 24 && latin >= 100 && english >= 4
      { "basis" => "正文或实际选段的字形与常用词规则", "han_characters" => han,
        "latin_characters" => latin, "simplified_markers" => simple, "traditional_markers" => traditional,
        "mixed" => mixed, "uncertain" => %w[other unknown zh].include?(detect(text)) || mixed }
    end

    def self.query_matches?(query, policy, entities: [])
      return true if policy["codes"].empty? || !%w[en zh-Hans zh-Hant zh].include?(policy["preferred"])
      text = query.gsub(/(?<!\S)lang:[a-z,-]+/i, "").gsub(/-?site:\S+|(?:after|before):\S+/i, "")
      han = text.scan(/\p{Han}/).length
      if policy["preferred"] == "en"
        Array(entities).select { |entity| entity.is_a?(String) && !entity.empty? }.each { |entity| text = text.gsub(entity, " ") }
        return text.scan(/\p{Han}/).empty?
      end
      return false if han.zero?
      script = detect(text)
      policy["preferred"] == "zh" || script == policy["preferred"] || script == "zh"
    end

    LANGUAGE_NAMES = /简体中文|簡體中文|繁体中文|繁體中文|中文|英文|英语|英語|simplified\s+Chinese|traditional\s+Chinese|English|Chinese/i

    def self.code(name)
      return "zh-Hans" if name.match?(/简体|簡體|simplified/i)
      return "zh-Hant" if name.match?(/繁体|繁體|traditional/i)
      name.match?(/中文|Chinese/i) ? "zh" : "en"
    end

    def self.preference(question)
      clauses = question.split(/[，,。；;！？!?\n]/)
      negative = /不(?:要|得|应|能|想|用|看|查|找|搜|需要|使用|引用|希望|允许)|别|別|无需|無需|避免|排除|拒绝|拒絕/
      excluded = []
      clauses.each do |clause|
        patterns = [/#{negative}(?:使用|引用|检索|檢索|采用|採用|查找|搜索|提供|看|查|找|搜|用)?\s*(#{LANGUAGE_NAMES})/,
                    /(#{LANGUAGE_NAMES})(?:的)?(?:资料|資料|来源|來源|原文)?\s*#{negative}/,
                    /\b(?:do\s+not|don't|avoid|exclude|without|no)\s+(?:(?:use|cite|include)\s+)?(#{LANGUAGE_NAMES})/i]
        patterns.each { |pattern| clause.scan(pattern) { |name| excluded << code(name[0]) } }
      end
      explicit = question[/\blang:([a-z]{2,3}(?:,[a-z]{2,3})*)/i, 1]
      if explicit
        codes = explicit.downcase.split(",").uniq
        return { "preferred" => codes.join(","), "codes" => codes, "strict" => true, "excluded" => excluded.uniq }
      end
      requested = lambda do |pattern|
        clauses.map do |clause|
          match = pattern.match(clause)
          match if match && !match.pre_match.match?(negative) && !match.pre_match.match?(/\b(?:not|don't|never|avoid|without)\s+(?:(?:just|only|use|using|cite|consult|restrict|to)\s+)*\z/i) && !match.post_match.match?(/\A\s*#{negative}/)
        end.compact.first
      end
      preferred = detect(question, question: true)
      strict_request = requested.call(/(?:只|仅|僅|限定)(?:用|使用|引用|看|查|搜)?(#{LANGUAGE_NAMES})|\b(?:only|exclusively)\s+(?:(?:use|cite|consult)\s+)?(#{LANGUAGE_NAMES})/i)
      if strict_request
        preferred = code(strict_request[1] || strict_request[2])
      else
        request = requested.call(/(#{LANGUAGE_NAMES})(?:的)?(?:资料|資料|来源|來源|原文)|((?:English|Chinese|simplified\s+Chinese|traditional\s+Chinese))\s+sources/i)
        preferred = code(request[1] || request[2]) if request
        chinese_priority = requested.call(/(?:优先|優先)(?:用|使用|引用|看|查|搜)?(中文)/)
        preferred = "zh" if chinese_priority
      end
      provider = preferred.start_with?("zh") ? "zh" : %w[en ja ko].include?(preferred) ? preferred : nil
      { "preferred" => preferred, "codes" => provider ? [provider] : [], "strict" => !!strict_request, "excluded" => excluded.uniq }
    end

    def self.allowed?(language, policy)
      !policy.fetch("excluded", []).any? { |code| code == language || (code == "zh" && language.start_with?("zh")) }
    end

    def self.match?(language, policy)
      preferred = policy["preferred"]
      return false unless allowed?(language, policy)
      return true if policy["codes"].empty? || (policy["codes"] - %w[zh en ja ko]).any?
      return language == preferred || language == "zh" if %w[zh-Hans zh-Hant].include?(preferred)
      policy["codes"].any? { |code| language == code || (code == "zh" && language.start_with?("zh")) }
    end

    def self.priority(language, policy)
      return 0 if match?(language, policy)
      return 1 if language.start_with?("zh") && policy["preferred"].start_with?("zh")
      %w[unknown other].include?(language) ? 3 : 2
    end

    def self.label(code)
      LABELS.fetch(code, code)
    end
  end
end
