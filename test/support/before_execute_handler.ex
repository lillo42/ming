defmodule Ming.BeforeExecuteHandler do
  @moduledoc false

  def before(context) do
    if context.request.value == "reject" do
      {:error, :rejected}
    else
      :ok
    end
  end

  def execute(%Ming.ExampleCommand1{}, _context), do: :ok
end
