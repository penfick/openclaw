import Foundation

// Built-in provider catalog. Mirrors Windows ProviderCatalog.cs (38 entries).
// Covers the mainstream providers in the openclaw install wizard.

struct ProviderDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let category: String
    let api: String
    /// nil for official/other providers (built-in known endpoints); "" for custom.
    let defaultBaseUrl: String?
    let defaultModelId: String
    let showBaseUrl: Bool
    let showModelId: Bool

    /// Friendly category label shown in the add-provider sheet (Windows SelectedHint).
    var categoryHint: String {
        switch self.category {
        case "official": return "官方 Provider"
        case "compatible": return "OpenAI 兼容"
        case "cn": return "国内 Provider"
        case "local": return "本地推理"
        case "custom": return "自定义端点"
        default: return self.category
        }
    }
}

enum ProviderCatalog {
    /// Display order: official → compatible → cn → local → other → custom.
    static let groups: [(title: String, category: String)] = [
        ("官方", "official"),
        ("国际兼容", "compatible"),
        ("国内", "cn"),
        ("本地", "local"),
        ("其他", "other"),
        ("自定义", "custom"),
    ]

    static let builtIn: [ProviderDefinition] = [
        // ── 官方 ──
        ProviderDefinition(id: "anthropic", name: "Anthropic", icon: "🅰", category: "official", api: "anthropic-messages", defaultBaseUrl: nil, defaultModelId: "claude-sonnet-4-6", showBaseUrl: false, showModelId: false),
        ProviderDefinition(id: "openai", name: "OpenAI", icon: "🟢", category: "official", api: "openai-responses", defaultBaseUrl: nil, defaultModelId: "gpt-4o", showBaseUrl: false, showModelId: false),
        ProviderDefinition(id: "google", name: "Google Gemini", icon: "🔵", category: "official", api: "google-generative-ai", defaultBaseUrl: nil, defaultModelId: "gemini-2.5-pro", showBaseUrl: false, showModelId: false),

        // ── 国际兼容 ──
        ProviderDefinition(id: "openrouter", name: "OpenRouter", icon: "🔀", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://openrouter.ai/api/v1", defaultModelId: "anthropic/claude-sonnet-4-6", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "together", name: "Together AI", icon: "🤝", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.together.xyz/v1", defaultModelId: "meta-llama/Llama-3.3-70B-Instruct-Turbo", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "venice", name: "Venice AI", icon: "🏛️", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.venice.ai/api/v1", defaultModelId: "llama-3.3-70b", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "deepseek", name: "DeepSeek", icon: "🐳", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.deepseek.com/v1", defaultModelId: "deepseek-chat", showBaseUrl: false, showModelId: false),
        ProviderDefinition(id: "groq", name: "Groq", icon: "⚡", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.groq.com/openai/v1", defaultModelId: "llama-3.3-70b-versatile", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "fireworks", name: "Fireworks", icon: "🎆", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.fireworks.ai/inference/v1", defaultModelId: "accounts/fireworks/models/llama-v3p3-70b-instruct", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "cerebras", name: "Cerebras", icon: "🧠", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.cerebras.ai/v1", defaultModelId: "llama-3.3-70b", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "mistral", name: "Mistral", icon: "🌬️", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.mistral.ai/v1", defaultModelId: "mistral-large-latest", showBaseUrl: false, showModelId: false),
        ProviderDefinition(id: "xai", name: "xAI Grok", icon: "❌", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.x.ai/v1", defaultModelId: "grok-3", showBaseUrl: false, showModelId: false),
        ProviderDefinition(id: "perplexity", name: "Perplexity", icon: "🔮", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.perplexity.ai", defaultModelId: "sonar-pro", showBaseUrl: false, showModelId: false),
        ProviderDefinition(id: "nvidia", name: "NVIDIA NIM", icon: "💎", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://integrate.api.nvidia.com/v1", defaultModelId: "nvidia/llama-3.1-nemotron-70b-instruct", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "deepinfra", name: "DeepInfra", icon: "🏗️", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.deepinfra.com/v1/openai", defaultModelId: "meta-llama/Llama-3.3-70B-Instruct", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "novita", name: "Novita AI", icon: "🚀", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.novita.ai/v3/openai", defaultModelId: "deepseek/deepseek-r1", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "huggingface", name: "Hugging Face", icon: "🤗", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api-inference.huggingface.co/v1", defaultModelId: "meta-llama/Llama-3.3-70B-Instruct", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "chutes", name: "Chutes AI", icon: "🎯", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.chutes.ai/v1", defaultModelId: "chutes/deepseek-r1", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "arcee", name: "Arcee AI", icon: "🔥", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://api.arcee.ai/v1", defaultModelId: "arcee-ai/arcee-blitz", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "vercel-ai-gateway", name: "Vercel Gateway", icon: "▲", category: "compatible", api: "openai-completions", defaultBaseUrl: "https://ai-gateway.vercel.sh/v1", defaultModelId: "openai/gpt-4o", showBaseUrl: true, showModelId: true),

        // ── 国内 ──
        ProviderDefinition(id: "zai", name: "Z.AI 智谱", icon: "✨", category: "cn", api: "openai-completions", defaultBaseUrl: "https://open.bigmodel.cn/api/paas/v4", defaultModelId: "glm-4.7", showBaseUrl: true, showModelId: false),
        ProviderDefinition(id: "xiaomi", name: "小米 mimo", icon: "📱", category: "cn", api: "openai-completions", defaultBaseUrl: "https://api.xiaomimimo.com/v1", defaultModelId: "mimo-v2.5-pro", showBaseUrl: true, showModelId: false),
        ProviderDefinition(id: "moonshot", name: "Moonshot Kimi", icon: "🌙", category: "cn", api: "openai-completions", defaultBaseUrl: "https://api.moonshot.cn/v1", defaultModelId: "kimi-k2", showBaseUrl: true, showModelId: false),
        ProviderDefinition(id: "qwen", name: "通义千问", icon: "🌐", category: "cn", api: "openai-completions", defaultBaseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModelId: "qwen-max", showBaseUrl: true, showModelId: false),
        ProviderDefinition(id: "qianfan", name: "百度千帆", icon: "🔍", category: "cn", api: "openai-completions", defaultBaseUrl: "https://qianfan.baidubce.com/v2", defaultModelId: "ernie-4.0-8k-latest", showBaseUrl: true, showModelId: false),
        ProviderDefinition(id: "tencent", name: "腾讯混元", icon: "🐧", category: "cn", api: "openai-completions", defaultBaseUrl: "https://api.hunyuan.cloud.tencent.com/v1", defaultModelId: "hunyuan-turbos-latest", showBaseUrl: true, showModelId: false),
        ProviderDefinition(id: "volcengine", name: "火山方舟", icon: "⛰️", category: "cn", api: "openai-completions", defaultBaseUrl: "https://ark.cn-beijing.volces.com/api/v3", defaultModelId: "doubao-pro-32k", showBaseUrl: true, showModelId: false),
        ProviderDefinition(id: "minimax", name: "MiniMax", icon: "📏", category: "cn", api: "openai-completions", defaultBaseUrl: "https://api.minimax.chat/v1", defaultModelId: "abab6.5s-chat", showBaseUrl: true, showModelId: false),
        ProviderDefinition(id: "siliconflow", name: "硅基流动", icon: "🌊", category: "cn", api: "openai-completions", defaultBaseUrl: "https://api.siliconflow.cn/v1", defaultModelId: "deepseek-ai/DeepSeek-V3", showBaseUrl: true, showModelId: false),
        ProviderDefinition(id: "stepfun", name: "阶跃星辰", icon: "👣", category: "cn", api: "openai-completions", defaultBaseUrl: "https://api.stepfun.com/v1", defaultModelId: "step-2-16k", showBaseUrl: true, showModelId: false),

        // ── 本地 ──
        ProviderDefinition(id: "vllm", name: "vLLM", icon: "🖥️", category: "local", api: "openai-completions", defaultBaseUrl: "http://localhost:8000/v1", defaultModelId: "meta-llama/Llama-3.3-70B-Instruct", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "ollama", name: "Ollama", icon: "🦙", category: "local", api: "openai-completions", defaultBaseUrl: "http://localhost:11434/v1", defaultModelId: "llama3.2", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "lmstudio", name: "LM Studio", icon: "🎵", category: "local", api: "openai-completions", defaultBaseUrl: "http://localhost:1234/v1", defaultModelId: "local-model", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "sglang", name: "SGLang", icon: "⚡", category: "local", api: "openai-completions", defaultBaseUrl: "http://localhost:30000/v1", defaultModelId: "meta-llama/Llama-3.3-70B-Instruct", showBaseUrl: true, showModelId: true),
        ProviderDefinition(id: "litellm", name: "LiteLLM Proxy", icon: "🛡️", category: "local", api: "openai-completions", defaultBaseUrl: "http://localhost:4000/v1", defaultModelId: "gpt-4o", showBaseUrl: true, showModelId: true),

        // ── 其他 ──
        ProviderDefinition(id: "github-copilot", name: "GitHub Copilot", icon: "🐙", category: "other", api: "openai-responses", defaultBaseUrl: nil, defaultModelId: "gpt-4o", showBaseUrl: false, showModelId: true),
        ProviderDefinition(id: "bedrock", name: "AWS Bedrock", icon: "☁️", category: "other", api: "openai-completions", defaultBaseUrl: nil, defaultModelId: "anthropic.claude-sonnet-4-6", showBaseUrl: false, showModelId: true),

        // ── 自定义 ──
        ProviderDefinition(id: "custom", name: "自定义 Provider", icon: "⚙️", category: "custom", api: "openai-completions", defaultBaseUrl: "", defaultModelId: "", showBaseUrl: true, showModelId: true),
    ]

    /// Look up a provider by id (Windows FindById).
    static func find(_ id: String) -> ProviderDefinition? {
        self.builtIn.first { $0.id == id }
    }

    /// Grouped by category, in display order (for the add-provider grid).
    static func grouped() -> [(title: String, providers: [ProviderDefinition])] {
        self.groups.map { (title, category) in
            (title, self.builtIn.filter { $0.category == category })
        }
    }
}
