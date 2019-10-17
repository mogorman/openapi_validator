defmodule OpenapiValidator do
  def find_schema({method, schema_url}, %{paths: paths, specs: specs}) do
    spec_name = Map.get(paths, {method, schema_url}, "")
    Map.get(specs, spec_name, %{})
  end

  defp compile_spec(item) when is_binary(item) do
    item
    |> Jason.decode!()
    |> ExJsonSchema.Schema.resolve()
  end

  defp compile_spec(item) when is_map(item) do
    item
    |> ExJsonSchema.Schema.resolve()
  end

  def compile_specs(specs, results \\ %{})

  def compile_specs([], results) do
    results
  end

  def compile_specs([head | tail] = items, results) when is_list(items) do
    new_specs = compile_spec(head)
    merged_results = add_schema(new_specs, results)
    compile_specs(tail, merged_results)
  end

  def add_schema(new_specs, results) do
    case ExJsonSchema.Schema.get_fragment(new_specs, [
           :root,
           "paths",
         ]) do
      {:error, _} ->
        results

      {:ok, paths} ->
        ref = get_name(new_specs)
        old_paths = Map.get(results, :paths, %{})
        old_specs = Map.get(results, :specs, %{})

        new_paths =
          Enum.map(List.flatten(build_routes(paths)), fn item -> {item, ref} end)
          |> Map.new()

        results
        |> Map.put(:paths, Map.merge(old_paths, new_paths))
        |> Map.put(:specs, Map.put(old_specs, ref, new_specs))
    end
  end

  defp build_route(route_name, methods) do
    Enum.map(
      methods,
      fn method ->
        method = String.upcase(method)
        {method, route_name}
      end
    )
  end

  defp build_routes(api_routes) do
    #    router = Module.concat(app, Router)

    Enum.map(
      api_routes,
      fn {route_name, route} ->
        build_route(route_name, Map.keys(route))
      end
    )
  end

  defp get_name(schema) do
    case ExJsonSchema.Schema.get_fragment(schema, [
           :root,
           "info",
         ]) do
      {:error, _} ->
        false

      {:ok, result} ->
        Map.get(result, "title")
    end
  end
end
