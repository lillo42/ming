defmodule Ming.PipelineTest do
  use ExUnit.Case

  alias Ming.Pipeline

  describe "assign/3" do
    test "stores value under atom key" do
      pipeline = %Pipeline{}
      updated = Pipeline.assign(pipeline, :user_id, 42)
      assert updated.assigns.user_id == 42
    end

    test "accumulates multiple assignments" do
      pipeline =
        %Pipeline{}
        |> Pipeline.assign(:a, 1)
        |> Pipeline.assign(:b, 2)

      assert pipeline.assigns == %{a: 1, b: 2}
    end

    test "overwrites existing key" do
      pipeline =
        %Pipeline{}
        |> Pipeline.assign(:key, 1)
        |> Pipeline.assign(:key, 2)

      assert pipeline.assigns.key == 2
    end
  end

  describe "assign_metadata/3" do
    test "stores metadata with atom key" do
      pipeline = %Pipeline{metadata: %{}}
      updated = Pipeline.assign_metadata(pipeline, :tag, "test")
      assert updated.metadata[:tag] == "test"
    end

    test "stores metadata with binary key" do
      pipeline = %Pipeline{metadata: %{}}
      updated = Pipeline.assign_metadata(pipeline, "tag", "test")
      assert updated.metadata["tag"] == "test"
    end
  end

  describe "halted?/1" do
    test "returns false for fresh pipeline" do
      refute Pipeline.halted?(%Pipeline{})
    end

    test "returns true after halt" do
      pipeline = Pipeline.halt(%Pipeline{})
      assert Pipeline.halted?(pipeline)
    end
  end

  describe "halt/1" do
    test "sets halted flag" do
      pipeline = Pipeline.halt(%Pipeline{})
      assert pipeline.halted == true
    end

    test "sets error response" do
      pipeline = Pipeline.halt(%Pipeline{})
      assert Pipeline.response(pipeline) == {:error, :halted}
    end
  end

  describe "respond/2" do
    test "sets response when nil" do
      pipeline = Pipeline.respond(%Pipeline{}, {:ok, :result})
      assert Pipeline.response(pipeline) == {:ok, :result}
    end

    test "ignores subsequent responses" do
      pipeline =
        %Pipeline{}
        |> Pipeline.respond({:ok, :first})
        |> Pipeline.respond({:ok, :second})

      assert Pipeline.response(pipeline) == {:ok, :first}
    end
  end

  describe "chain/3" do
    defmodule NoOpMiddleware do
      @behaviour Ming.Middleware
      def init(opts), do: opts
      def before_dispatch(pipeline, _opts), do: pipeline
      def after_dispatch(pipeline, _opts), do: pipeline
      def after_failure(pipeline, _opts), do: pipeline
    end

    defmodule AssigningMiddleware do
      @behaviour Ming.Middleware
      def init(opts), do: opts
      def before_dispatch(pipeline, _opts), do: Pipeline.assign(pipeline, :seen, true)
      def after_dispatch(pipeline, _opts), do: Pipeline.assign(pipeline, :seen, true)
      def after_failure(pipeline, _opts), do: Pipeline.assign(pipeline, :seen, true)
    end

    defmodule HaltingMiddleware do
      @behaviour Ming.Middleware
      def init(opts), do: opts
      def before_dispatch(pipeline, _opts), do: Pipeline.halt(pipeline)
      def after_dispatch(pipeline, _opts), do: Pipeline.halt(pipeline)
      def after_failure(pipeline, _opts), do: Pipeline.halt(pipeline)
    end

    test "runs all middleware in order" do
      pipeline =
        %Pipeline{}
        |> Pipeline.chain(:before_dispatch, [
          {AssigningMiddleware, []},
          {NoOpMiddleware, []}
        ])

      assert pipeline.assigns.seen == true
    end

    test "halts before_dispatch early" do
      pipeline =
        %Pipeline{}
        |> Pipeline.chain(:before_dispatch, [
          {HaltingMiddleware, []},
          {AssigningMiddleware, []}
        ])

      assert Pipeline.halted?(pipeline)
      refute Map.has_key?(pipeline.assigns, :seen)
    end

    test "halts after_dispatch early" do
      pipeline =
        %Pipeline{response: {:ok, []}}
        |> Pipeline.chain(:after_dispatch, [
          {HaltingMiddleware, []},
          {AssigningMiddleware, []}
        ])

      assert Pipeline.halted?(pipeline)
      refute Map.has_key?(pipeline.assigns, :seen)
    end

    test "runs all after_failure middleware even when halted" do
      pipeline =
        %Pipeline{response: {:error, :bad}}
        |> Pipeline.chain(:after_failure, [
          {AssigningMiddleware, []},
          {HaltingMiddleware, []}
        ])

      assert Pipeline.halted?(pipeline)
      assert pipeline.assigns.seen == true
    end

    test "returns pipeline for empty middleware" do
      pipeline = %Pipeline{}
      assert Pipeline.chain(pipeline, :before_dispatch, []) == pipeline
    end

    test "works with bare module (no opts tuple)" do
      pipeline =
        %Pipeline{}
        |> Pipeline.chain(:before_dispatch, [NoOpMiddleware])

      refute Pipeline.halted?(pipeline)
    end
  end
end
