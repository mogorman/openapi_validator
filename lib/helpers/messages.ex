defmodule OpenapiValidator.Helpers.Messages do
  def get_stock_message(:not_found) do
    %{
      "message" => %{
        "type" => "error",
        "title" => "Failed",
        "description" => "Schema not implemented",
      },
    }
  end
end
