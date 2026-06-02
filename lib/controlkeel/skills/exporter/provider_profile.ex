defmodule ControlKeel.Skills.Exporter.ProviderProfile do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    readme_path = Path.join(root, "provider-profiles/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, E.provider_profile_contents(project_root, opts))

    profile_templates = [
      {"codestral.json",
       %{
         "provider" => "openai",
         "model" => "codestral-latest",
         "base_url" => "https://api.mistral.ai/v1",
         "note" =>
           "Use this as a CK-owned provider profile or proxy template for Codestral-compatible APIs."
       }},
      {"vllm.json",
       %{
         "provider" => "openai",
         "model" => "Qwen/Qwen2.5-Coder-32B-Instruct",
         "base_url" => "http://127.0.0.1:8000",
         "note" =>
           "vLLM exposes an OpenAI-compatible server. Set this base URL and model, then optionally add a token if your deployment requires one."
       }},
      {"sglang.json",
       %{
         "provider" => "openai",
         "model" => "Qwen/Qwen2.5-Coder-32B-Instruct",
         "base_url" => "http://127.0.0.1:30000",
         "note" =>
           "SGLang commonly exposes an OpenAI-compatible HTTP endpoint. Adjust host, port, and model to match your deployment."
       }},
      {"lmstudio.json",
       %{
         "provider" => "openai",
         "model" => "local-model",
         "base_url" => "http://127.0.0.1:1234",
         "note" =>
           "LM Studio local server speaks an OpenAI-compatible API. ControlKeel can use it through the OpenAI provider path with a custom base URL."
       }},
      {"huggingface.json",
       %{
         "provider" => "openai",
         "model" => "meta-llama/Llama-3.1-8B-Instruct:cerebras",
         "base_url" => "https://router.huggingface.co",
         "note" =>
           "Hugging Face Inference Providers expose OpenAI-compatible chat-completion APIs and require an HF token."
       }},
      {"ollama.json",
       %{
         "provider" => "ollama",
         "model" => "qwen2.5:7b",
         "base_url" => "http://127.0.0.1:11434",
         "note" =>
           "Use the native Ollama provider path when you want local chat and embeddings without an external API key."
       }}
    ]

    writes =
      Enum.map(profile_templates, fn {filename, payload} ->
        path = Path.join(root, "provider-profiles/#{filename}")
        File.write!(path, Jason.encode!(payload, pretty: true) <> "\n")
        %{"path" => path, "kind" => "settings"}
      end)

    E.with_common_assets(
      root,
      project_root,
      opts,
      [%{"path" => readme_path, "kind" => "runtime"} | writes],
      [
        "Use these templates with `controlkeel provider set-key`, `set-base-url`, `set-model`, and `default` flows.",
        "OpenAI-compatible backends such as vLLM, SGLang, LM Studio, Hugging Face, and Codestral use the CK OpenAI provider path with a custom base URL."
      ]
    )
  end
end
