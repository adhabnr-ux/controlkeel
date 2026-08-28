defmodule ControlKeel.Memory.Embeddings do
  @moduledoc false

  alias ControlKeel.Memory.Embedding
  alias ControlKeel.Memory.Record
  alias ControlKeel.Memory.Providers.{Ollama, OpenAI, OpenRouter}
  alias ControlKeel.ProviderBroker
  alias ControlKeel.Repo

  def embed(text, opts \\ []) when is_binary(text) do
    providers = providers(opts)

    Enum.reduce_while(providers, {:error, :unavailable}, fn provider, _acc ->
      case provider_embed(provider, text, opts) do
        {:ok, payload} -> {:halt, {:ok, payload}}
        _error -> {:cont, {:error, :unavailable}}
      end
    end)
  end

  @chunk_size 512
  @chunk_overlap 64
  @max_chunk_tokens 512

  def upsert_record_embedding(%Record{} = record, opts \\ []) do
    body_chunks = chunk_body(record.body)

    if body_chunks == [] do
      upsert_single_embedding(record, document(record), opts)
    else
      # Embed each chunk with metadata; store first chunk as primary embedding
      # and subsequent chunks as additional rows with chunk_index in metadata.
      base_doc = document_without_body(record)

      results =
        body_chunks
        |> Enum.with_index()
        |> Enum.map(fn {chunk, idx} ->
          text = if idx == 0, do: base_doc <> "\n" <> chunk, else: chunk
          {idx, text}
        end)
        |> Enum.map(fn {idx, text} ->
          case embed(text, opts) do
            {:ok, payload} ->
              attrs = %{
                memory_record_id: record.id,
                provider: payload.provider,
                model: payload.model <> chunk_suffix(idx),
                dimensions: length(payload.embedding),
                embedding: payload.embedding
              }

              result =
                %Embedding{}
                |> Embedding.changeset(attrs)
                |> Repo.insert(
                  on_conflict: [
                    set: [
                      dimensions: attrs.dimensions,
                      embedding: attrs.embedding,
                      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
                    ]
                  ],
                  conflict_target: [:memory_record_id, :provider, :model, :chunk_index]
                )

              {idx, result}

            error ->
              {idx, error}
          end
        end)

      # Return primary chunk result (idx 0) if available
      case Enum.find(results, fn {idx, _} -> idx == 0 end) do
        {0, {:ok, embedding}} -> {:ok, embedding}
        {0, error} -> error
        nil -> {:error, :unavailable}
      end
    end
  end

  defp upsert_single_embedding(record, text, opts) do
    with {:ok, payload} <- embed(text, opts) do
      attrs = %{
        memory_record_id: record.id,
        provider: payload.provider,
        model: payload.model,
        dimensions: length(payload.embedding),
        embedding: payload.embedding
      }

      %Embedding{}
      |> Embedding.changeset(attrs)
      |> Repo.insert(
        on_conflict: [
          set: [
            dimensions: attrs.dimensions,
            embedding: attrs.embedding,
            updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
          ]
        ],
        conflict_target: [:memory_record_id, :provider, :model, :chunk_index]
      )
    else
      {:error, :unavailable} -> {:error, :unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp chunk_suffix(0), do: ""
  defp chunk_suffix(idx), do: "_chunk_#{idx}"

  @doc false
  def chunk_body(nil), do: []
  def chunk_body(""), do: []

  def chunk_body(body) when is_binary(body) do
    tokens = String.split(body, ~r/\s+/u, trim: true)

    if length(tokens) <= @max_chunk_tokens do
      []
    else
      tokens
      |> Enum.chunk_every(@chunk_size, @chunk_size - @chunk_overlap)
      |> Enum.map(&Enum.join(&1, " "))
    end
  end

  def document(%Record{} = record) do
    [record.title, record.summary, record.body, Enum.join(record.tags || [], " ")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp document_without_body(%Record{} = record) do
    [record.title, record.summary, Enum.join(record.tags || [], " ")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp providers(opts) do
    override = Application.get_env(:controlkeel, :memory_embedding_providers_override)

    cond do
      is_list(override) and override != [] ->
        override

      true ->
        project_root = opts[:project_root] || File.cwd!()
        provider_env = opts[:provider] || System.get_env("CONTROLKEEL_EMBEDDINGS_PROVIDER")

        base =
          case provider_env do
            nil ->
              configured_providers(project_root)

            "none" ->
              []

            value when is_binary(value) ->
              [resolved_provider(value, project_root, opts)]

            value when is_atom(value) ->
              [resolved_provider(Atom.to_string(value), project_root, opts)]

            _value ->
              configured_providers(project_root)
          end

        base
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(fn
          %{provider: provider} -> provider
          other -> other
        end)
    end
  rescue
    ArgumentError -> configured_providers(File.cwd!())
  end

  defp provider_embed({module, provider_opts}, text, _opts)
       when is_atom(module) and is_list(provider_opts) do
    apply(module, :embed, [text, provider_opts])
  end

  defp provider_embed(%{provider: "ollama", config: config}, text, _opts),
    do: Ollama.embed(text, normalize_config(config))

  defp provider_embed(%{provider: "openai", config: config}, text, _opts),
    do: OpenAI.embed(text, normalize_config(config))

  defp provider_embed(%{provider: "openrouter", config: config}, text, _opts),
    do: OpenRouter.embed(text, normalize_config(config))

  defp provider_embed(:ollama, text, opts), do: Ollama.embed(text, opts)
  defp provider_embed(:openai, text, opts), do: OpenAI.embed(text, opts)
  defp provider_embed(:openrouter, text, opts), do: OpenRouter.embed(text, opts)
  defp provider_embed(_provider, _text, _opts), do: {:error, :unavailable}

  defp configured_providers(project_root) do
    ProviderBroker.embeddings_chain(project_root)
  end

  defp resolved_provider(provider, project_root, opts) do
    ProviderBroker.resolve_provider(provider, project_root, opts)
  end

  defp normalize_config(config) when is_list(config), do: config
  defp normalize_config(config) when is_map(config), do: Enum.into(config, [])
  defp normalize_config(_config), do: []
end
