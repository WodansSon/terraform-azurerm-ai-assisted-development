[CmdletBinding()]
param(
    [Parameter()]
    [string] $IconDirectory = (Join-Path $PSScriptRoot '../../../workbench/icons/llms')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WorkbenchIconPreview.ps1')

$commit = '8a1b2821bb768c484fe8da20c5e1838b6bf551a9'
$iconNames = @(
    'ace', 'adobe', 'adobefirefly', 'agentvoice', 'agnesai',
    'agui', 'ai2', 'ai21', 'ai302', 'ai360',
    'aihubmix', 'aimass', 'aionlabs', 'airjelly', 'aistudio',
    'akashchat', 'alephalpha', 'alibaba', 'alibabacloud', 'amdradeoncloud',
    'amp', 'anspire', 'antgroup', 'anthropic', 'antigravity',
    'anyscale', 'apertis', 'apple', 'arcee', 'askverdict',
    'assemblyai', 'atlascloud', 'automatic', 'aws', 'aya',
    'azure', 'azureai', 'baai', 'baichuan', 'baidu',
    'baiducloud', 'bailian', 'baseten', 'bedrock', 'bfl',
    'bilibili', 'bilibiliindex', 'bing', 'bocha', 'brave',
    'briaai', 'browserless', 'burncloud', 'bytedance', 'capcut',
    'celestoai', 'centml', 'cerebras', 'chatglm', 'cherrystudio',
    'chutes', 'civitai', 'claude', 'claudecode', 'cline',
    'clipdrop', 'cloudflare', 'codebuddy', 'codeflicker', 'codegeex',
    'codex', 'cogvideo', 'cogview', 'cohere', 'colab',
    'cometapi', 'comfyui', 'commanda', 'commandcode', 'copilot',
    'copilotkit', 'coqui', 'coze', 'crewai', 'crusoe',
    'cursor', 'cybercut', 'dalle', 'dbrx', 'decart',
    'deepai', 'deepcogito', 'deepinfra', 'deepl', 'deepmind',
    'deepseek', 'devin', 'dify', 'digitalocean', 'doc2x',
    'docsearch', 'dolphin', 'dotsstudio', 'doubao', 'dreammachine',
    'elevenlabs', 'elevenx', 'essentialai', 'exa', 'fal',
    'fastgpt', 'featherless', 'figma', 'firecrawl', 'fireworks',
    'fishaudio', 'flora', 'flowith', 'flux', 'friendli',
    'gemini', 'geminicli', 'gemma', 'giteeai', 'github',
    'githubcopilot', 'glama', 'glif', 'glmv', 'gmicloud',
    'google', 'googlecloud', 'goose', 'gradio', 'greptile',
    'grok', 'groq', 'hailuo', 'haiper', 'happyhorse',
    'hedra', 'hermesagent', 'higress', 'huawei', 'huaweicloud',
    'huggingface', 'hunyuan', 'hyperbolic', 'ibm', 'ideogram',
    'iflytekcloud', 'inception', 'inceptron', 'inference', 'infermatic',
    'infinigence', 'inflection', 'internlm', 'ionet', 'jimeng',
    'jina', 'junie', 'kagi', 'kilocode', 'kimi',
    'kiro', 'kling', 'kluster', 'kolors', 'krea',
    'kwaikat', 'kwaipilot', 'lambda', 'langchain', 'langfuse',
    'langgraph', 'langsmith', 'leptonai', 'lg', 'lightricks',
    'liquid', 'livekit', 'llamaindex', 'llava', 'llmapi',
    'lmstudio', 'lobehub', 'longcat', 'lovable', 'lovart',
    'luma', 'magic', 'make', 'manus', 'mastra',
    'mcp', 'mcpso', 'menlo', 'meshy', 'meta',
    'metaai', 'metagpt', 'microsoft', 'midjourney', 'minimax',
    'mistral', 'modelscope', 'monica', 'moonshot', 'morph',
    'moxt', 'myshell', 'n8n', 'nanobanana', 'nebius',
    'newapi', 'nextbit', 'notebooklm', 'notion', 'nousresearch',
    'nova', 'novelai', 'novita', 'nplcloud', 'nvidia',
    'obsidian', 'ollama', 'openai', 'openchat', 'openclaw',
    'opencode', 'openhands', 'openhuman', 'openrouter', 'openwebui',
    'palm', 'parasail', 'perceptron', 'perplexity', 'phala',
    'phidata', 'phind', 'pi', 'pika', 'pixverse',
    'player2', 'poe', 'pollinations', 'poolside', 'ppio',
    'prunaai', 'pydanticai', 'qingyan', 'qiniu', 'qoder',
    'qwen', 'railway', 'recraft', 'reka', 'relace',
    'replicate', 'replit', 'reve', 'roocode', 'rsshub',
    'runway', 'rwkv', 'sakana', 'sambanova', 'search1api',
    'searchapi', 'searxng', 'sensenova', 'siliconcloud', 'sillytavern',
    'skywork', 'slock', 'smithery', 'snowflake', 'sophnet',
    'sora', 'spark', 'speedai', 'stability', 'statecloud',
    'stepfun', 'straico', 'streamlake', 'submodel', 'suno',
    'sync', 'targon', 'tavily', 'tencent', 'tencentcloud',
    'tiangong', 'tii', 'together', 'topazlabs', 'trae',
    'tripo', 'turix', 'udio', 'unionalpha', 'unsloth',
    'unstructured', 'upstage', 'v0', 'vectorizerai', 'venice',
    'vercel', 'vertexai', 'vidu', 'viggle', 'vllm',
    'volcengine', 'voyage', 'wafer', 'wandb', 'wavespeed',
    'wenxin', 'windsurf', 'workersai', 'worldrouter', 'xai',
    'xiaomimimo', 'xinference', 'xpay', 'xuanyuan', 'yandex',
    'yi', 'youmind', 'yuanbao', 'zai', 'zapier',
    'zeabur', 'zencoder', 'zenmux', 'zeroone', 'zhipu'
)

if (-not (Test-Path -LiteralPath $IconDirectory -PathType Container)) {
    throw "The vendored LLM icon directory '$IconDirectory' does not exist."
}
if (-not (Test-Path -LiteralPath (Join-Path $IconDirectory 'LICENSE.txt') -PathType Leaf)) {
    throw "The vendored LLM icon license is missing from '$IconDirectory'."
}

$symbols = foreach ($iconName in $iconNames) {
    $sourcePath = Join-Path $IconDirectory "$iconName.svg"
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "The vendored LLM icon '$iconName' is missing from '$IconDirectory'."
    }
    $svg = (Get-Content -LiteralPath $sourcePath -Raw).Trim()
    $match = [regex]::Match($svg, '^<svg[^>]*viewBox="(?<viewBox>[^"]+)"[^>]*>(?<content>[\s\S]*)</svg>$')
    if (-not $match.Success -or $match.Groups['viewBox'].Value -notin @('0 0 24 24', '0 0 25 25', '0 0 320 320', '0 0 33 32', '0 0 64 64')) {
        throw "LLM icon '$iconName' does not use a supported SVG viewBox."
    }
    $viewBox = $match.Groups['viewBox'].Value
    $content = $match.Groups['content'].Value.Trim()
    if (-not $content) {
        throw "LLM icon '$iconName' is empty."
    }
    $document = [xml]$svg
    $presentation = foreach ($attributeName in @('fill', 'fill-rule')) {
        $value = $document.DocumentElement.GetAttribute($attributeName)
        if ($value) {
            " $attributeName=`"$([Security.SecurityElement]::Escape($value))`""
        }
    }
    $style = $document.DocumentElement.GetAttribute('style')
    if ($style -notin @('', 'flex:none;line-height:1', 'flex:none;line-height:1;filter:grayscale(100%)')) {
        throw "LLM icon '$iconName' has unsupported root styling."
    }
    if ($style.EndsWith(';filter:grayscale(100%)')) {
        $presentation += ' filter="grayscale(100%)"'
    }
    "  <symbol id=`"llm-$iconName`" viewBox=`"$viewBox`"$($presentation -join '')>$content</symbol>"
}

$sprite = @(
    '<svg xmlns="http://www.w3.org/2000/svg">'
    '<!-- Generated by hosted_copilot/tools/internal/workbench/New-WorkbenchLlmIconSprite.ps1. -->'
    '<!-- Source: https://github.com/lobehub/lobe-icons/tree/8a1b2821bb768c484fe8da20c5e1838b6bf551a9/packages/static-svg/icons -->'
    $symbols
    '</svg>'
) -join "`n"
$spritePath = Join-Path $IconDirectory 'sprite.svg'
[IO.File]::WriteAllText($spritePath, $sprite + "`n", [Text.UTF8Encoding]::new($false))
$previewPngPath = New-WorkbenchIconPreview -IconDirectory $IconDirectory -FamilyName 'Lobe Icons AI and LLM Brands' -Commit $commit -SymbolPrefix 'llm' -IconNames $iconNames

[pscustomobject]@{
    Status = 'generated'
    Commit = $commit
    IconCount = $iconNames.Count
    SpritePath = $spritePath
    PreviewPngPath = $previewPngPath
    LicensePath = (Join-Path $IconDirectory 'LICENSE.txt')
}
