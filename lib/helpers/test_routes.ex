defmodule OpenapiValidator.Helpers.TestRoutes do
  @moduledoc """
  Module for providing easy way for an application to test all of its loaded routes are valid.
  """

  defp prep_schemas(schemas, application) do
    Enum.map(
      schemas.paths,
      fn {{method, schema_url}, schema_name} ->
        case Phoenix.Router.route_info(
               Module.concat(application, Router),
               String.upcase(method),
               schema_url,
               ""
             ) do
          :error ->
            {false, schema_url, method}

          _ ->
            {true, schema_url, method}
        end
      end
    )
  end

  defp filter_valid_urls(urls, ignored_routes) do
    urls
    |> Enum.reject(fn {result, url, method} -> result == true end)
    |> Enum.reject(fn {result, url, method} ->
      Enum.any?(ignored_routes, fn {route_method, route_url} ->
        url == route_url && route_method == method
      end)
    end)
    |> Enum.map(fn {_result, url, method} -> {method, url} end)
  end

  def validate_routes(application, schemas, ignored_routes) do
    OpenapiValidator.compile_specs(schemas)
    |> prep_schemas(application)
    |> filter_valid_urls(ignored_routes)
  end
end
