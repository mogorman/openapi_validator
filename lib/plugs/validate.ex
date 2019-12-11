defmodule OpenapiValidator.Plugs.Validate do
  @moduledoc ~S"""
  Validates input and output according to one or more OpenAPI specs.

  Usage:

  Add the plug at the bottom of one or more pipelines in `router.ex`:

      pipeline "api" do
        # ...
        plug Api.Plugs.OASValidator, spec: Appcues.MobileApiSpecs.sdk()
      end
  """
  require Logger
  import Plug.Conn
  alias OpenapiValidator.Helpers.Errors

  @behaviour Plug

  @type path :: String.t()
  @type path_regex :: {path, Regex.t()}
  @type open_api_spec :: map()

  @impl Plug
  def init(%{specs: raw_specs} = opts) do
    resolved_specs = OpenapiValidator.compile_specs(raw_specs)

    # set empty defaults for specs and paths just in case
    Map.merge(opts, %{
      paths: %{},
      specs: %{},
      all_paths_required: Map.get(opts, :all_paths_required, false),
      custom_error: Map.get(opts, :custom_error, nil),
      explain_error: Map.get(opts, :explain_error, true),
      validate_params: Map.get(opts, :validate_params, true),
      validate_body: Map.get(opts, :validate_body, true),
      validate_response: Map.get(opts, :validate_response, true),
      output_stubs: Map.get(opts, :output_stubs, false),
      allow_invalid_input: Map.get(opts, :allow_invalid_input, false),
      allow_invalid_output: Map.get(opts, :allow_invalid_output, false),
    })
    |> Map.merge(resolved_specs)
  end

  def init(_opts) do
    Logger.error(
      "#{inspect(__MODULE__)}: specs are required but were not provided."
    )

    nil
  end

  @impl Plug
  def call(conn, opts) do
    # if validate output
    # Plug.Conn.register_before_send(conn, &HTML.minify_body/1)
    {method, schema_url} = get_schema_url_from_request(conn)
    schema = OpenapiValidator.find_schema({method, schema_url}, opts)
    found_schema_body(conn, opts, {schema, method, schema_url})
  end

  defp error_handler(conn, opts, error, info) do
    case Map.get(opts, :custom_error) do
      nil ->
        standard_error_handler(conn, opts, error, info)

      custom ->
        custom.error_handler(conn, opts, error, info)
    end
  end

  defp standard_error_handler(conn, opts, error, info) do
    message =
      case Map.get(opts, :explain_error) do
        true ->
          Jason.encode!(Errors.get_stock_message(error, info))

        false ->
          ""
      end

    conn
    |> put_resp_header("content-type", "application/json")
    |> resp(
      Errors.get_stock_code(error),
      message
    )
    |> halt()
  end

  defp found_schema_body(conn, opts, {schema, method, schema_url} = open_api)
       when schema == %{} do
    case Map.get(opts, :all_paths_required) do
      true ->
        Logger.info("No spec found for #{method}:#{schema_url}")
        error_handler(conn, opts, :not_found, {method, schema_url, nil})

      false ->
        Logger.info("No spec found for #{method}:#{schema_url}")
        conn
    end
  end

  defp found_schema_body(conn, opts, {schema, method, schema_url} = open_api) do
    case Map.get(opts, :validate_body) do
      true ->
        body_schema = get_body_fragment(open_api)
        is_body_required = is_body_required?(open_api)
        conn = conn |> Plug.Conn.fetch_query_params()

        case attempt_validate_body(
               body_schema,
               is_body_required,
               schema,
               conn.body_params
             ) do
          :ok ->
            validated_body(conn, opts, open_api)

          {false, errors} ->
            invalid_body(conn, opts, errors, open_api)
        end

      false ->
        validated_body(conn, opts, open_api)
    end
  end

  defp validated_body(conn, opts, {schema, _method, _schema_url} = open_api) do
    case Map.get(opts, :validate_params) do
      true ->
        params_schema = get_params_fragments(open_api)
        conn = conn |> Plug.Conn.fetch_query_params()

        case attempt_validate_params(params_schema, schema, conn) do
          :ok ->
            validated_params(conn, opts, open_api)

          {false, errors} ->
            invalid_params(conn, opts, errors, open_api)
        end

      false ->
        validated_params(conn, opts, open_api)
    end
  end

  defp validated_params(conn, opts, open_api) do
    case Map.get(opts, :validate_response) do
      true ->
        Plug.Conn.register_before_send(conn, fn conn ->
          validate_response(conn, Map.put(opts, :open_api, open_api))
        end)

      false ->
        conn
    end
  end

  def validate_response(conn, opts) do
    open_api = Map.get(opts, :open_api, {nil, nil, nil})
    {schema, method, schema_url} = open_api
    fragment = get_response_fragment({schema, method, schema_url}, conn.status)
    is_body_required = true

    body =
      case Jason.decode(conn.resp_body) do
        {:ok, json} -> json
        _ -> %{"error" => "invalid json"}
      end

    case attempt_validate_body(fragment, is_body_required, schema, body) do
      :ok ->
        conn

      {false, errors} ->
        case Map.get(opts, :allow_invalid_output) do
          true ->
            conn

          false ->
            error_handler(
              conn,
              opts,
              :invalid_response,
              {method, schema_url, %{body: body, errors: errors}}
            )
        end
    end
  end

  defp invalid_body(conn, opts, errors, {schema, method, schema_url} = open_api) do
    case Map.get(opts, :allow_invalid_input) do
      true ->
        Logger.info("Invalid request on #{method} #{schema_url}")
        validated_body(conn, opts, open_api)

      false ->
        Logger.warn("Invalid request on #{method} #{schema_url}")
        error_handler(conn, opts, :invalid_body, {method, schema_url, errors})
    end
  end

  defp invalid_params(
         conn,
         opts,
         errors,
         {schema, method, schema_url} = open_api
       ) do
    case Map.get(opts, :allow_invalid_input) do
      true ->
        Logger.info("Invalid request on #{method} #{schema_url}")
        validated_params(conn, opts, open_api)

      false ->
        Logger.warn("Invalid request on #{method} #{schema_url}")
        error_handler(conn, opts, :invalid_params, {method, schema_url, errors})
    end
  end

  defp attempt_validate_body(false, _is_body_required, _schema, payload)
       when payload == %{} do
    :ok
  end

  defp attempt_validate_body(false, false, _schema, _payload) do
    :ok
  end

  defp attempt_validate_body(false, _is_body_required, _schema, payload) do
    {false, %{unmatched_payload: payload}}
  end

  defp attempt_validate_body(fragment, _is_body_required, schema, payload) do
    case ExJsonSchema.Validator.validate_fragment(schema, fragment, payload) do
      :ok ->
        :ok

      {:error, result} ->
        name = String.split(fragment, "/") |> Enum.reverse() |> Enum.at(0)
        {false, %{name: name, reason: result |> Map.new()}}
    end
  end

  defp attempt_validate_params(false, schema, conn) do
    :ok
  end

  defp attempt_validate_params([], schema, conn) do
    :ok
  end

  defp attempt_validate_params(fragments, schema, conn) do
    headers = conn.req_headers |> Map.new()

    results =
      Enum.map(
        fragments,
        fn fragment_ref ->
          fragment = ExJsonSchema.Schema.get_fragment!(schema, fragment_ref)
          name = Map.get(fragment, "name")
          fragment_schema = Map.get(fragment, "schema")
          required = Map.get(fragment, "required", true)

          input_data =
            case Map.get(fragment, "in") do
              "path" ->
                Map.get(conn.path_params, name)

              "query" ->
                Map.get(conn.query_params, name)

              "header" ->
                Map.get(headers, name)
            end

          case is_nil(input_data) and required == false do
            true ->
              :ok

            false ->
              case ExJsonSchema.Validator.validate_fragment(
                     schema,
                     fragment_schema,
                     input_data
                   ) do
                :ok ->
                  :ok

                {:error, reason} ->
                  %{name: name, reason: reason |> Map.new()}
              end
          end
        end
      )
      |> Enum.reject(fn elem -> elem == :ok end)

    case results do
      [] ->
        :ok

      items ->
        {false, items}
    end
  end

  defp get_params_fragments({schema, method, schema_url}) do
    method = String.downcase(method)

    case ExJsonSchema.Schema.get_fragment(schema, [
           :root,
           "paths",
           schema_url,
           method,
           "parameters",
         ]) do
      {:error, _} ->
        false

      {:ok, result} ->
        Enum.map(result, fn elem ->
          ref = Map.get(elem, "$ref")

          Enum.reduce(ref, "", fn sub_elem, acc ->
            case sub_elem do
              :root -> "#"
              _ -> acc <> "/" <> sub_elem
            end
          end)
        end)
    end
  end

  defp is_body_required?({schema, method, schema_url}) do
    method = String.downcase(method)

    case ExJsonSchema.Schema.get_fragment(schema, [
           :root,
           "paths",
           schema_url,
           method,
           "requestBody",
           "required",
         ]) do
      {:error, _} ->
        true

      {:ok, result} ->
        result
    end
  end

  defp get_body_fragment({schema, method, schema_url}) do
    method = String.downcase(method)

    case ExJsonSchema.Schema.get_fragment(schema, [
           :root,
           "paths",
           schema_url,
           method,
           "requestBody",
           "content",
           "application/json",
           "schema",
           "$ref",
         ]) do
      {:error, _} ->
        false

      {:ok, result} ->
        Enum.reduce(result, "", fn elem, acc ->
          case elem do
            :root -> "#"
            _ -> acc <> "/" <> elem
          end
        end)
    end
  end

  defp get_response_fragment({schema, method, schema_url}, response_code) do
    method = String.downcase(method)

    case ExJsonSchema.Schema.get_fragment(schema, [
           :root,
           "paths",
           schema_url,
           method,
           "responses",
           "#{response_code}",
           "content",
           "application/json",
           "schema",
           "$ref",
         ]) do
      {:error, _} ->
        false

      {:ok, result} ->
        Enum.reduce(result, "", fn elem, acc ->
          case elem do
            :root -> "#"
            _ -> acc <> "/" <> elem
          end
        end)
    end
  end

  defp get_schema_url_from_request(conn) do
    router = (Map.get(conn, :private) || %{}) |> Map.get(:phoenix_router)

    case router do
      nil ->
        {nil, nil}

      _ ->
        route =
          Phoenix.Router.route_info(
            router,
            conn.method,
            conn.request_path,
            conn.host
          )

        schema_url =
          Enum.reduce(route.path_params, route.route, fn {param, _value},
                                                         path ->
            String.replace(path, ":#{param}", "{#{param}}")
          end)

        {conn.method, schema_url}
    end
  end
end
