defmodule MingTest do
  use ExUnit.Case
  doctest Ming

  test "greets the world" do
    assert Ming.hello() == :world
  end
end
