defmodule Ming.Message.Middleware.ApplyPublicationDefaultsTest do
  use ExUnit.Case

  alias Ming.Context
  alias Ming.Message
  alias Ming.Message.Middleware.ApplyPublicationDefaults

  defp context(message, publication, metadata \\ %{}) do
    %Context{
      assigns: %{publication: publication},
      metadata: metadata,
      request: message,
      routing_key: :ming_produce_message,
      timeout: :infinity
    }
  end

  describe "before_handle/1" do
    test "fills missing fields from publication configuration" do
      message = %Message{
        id: "msg-1",
        payload: "data",
        routing_key: :order_created,
        timestamp: DateTime.utc_now(),
        headers: %{}
      }

      publication = [
        source: "my-app",
        subject: "orders"
      ]

      result = ApplyPublicationDefaults.before_handle(context(message, publication))

      assert result.request.source == "my-app"
      assert result.request.subject == "orders"
      assert result.request.content_type == "text/plain"
    end

    test "keeps message values over publication defaults" do
      message = %Message{
        id: "msg-1",
        payload: "data",
        routing_key: :order_created,
        timestamp: DateTime.utc_now(),
        source: "existing-source",
        headers: %{}
      }

      publication = [source: "my-app"]
      result = ApplyPublicationDefaults.before_handle(context(message, publication))

      assert result.request.source == "existing-source"
    end

    test "merges headers from publication, metadata and message" do
      message = %Message{
        id: "msg-1",
        payload: "data",
        routing_key: :order_created,
        timestamp: DateTime.utc_now(),
        headers: %{"x-msg" => "msg"}
      }

      publication = [default_headers: %{"x-pub" => "pub"}]
      metadata = %{headers: %{"x-meta" => "meta"}}

      result = ApplyPublicationDefaults.before_handle(context(message, publication, metadata))

      assert result.request.headers == %{"x-pub" => "pub", "x-meta" => "meta", "x-msg" => "msg"}
    end

    test "halts when request is not a message" do
      ctx = context(%{"not" => "a message"}, [])
      result = ApplyPublicationDefaults.before_handle(ctx)

      assert Context.halted?(result)
      assert Context.response(result) == {:error, :invalid_params}
    end

    test "halts when publication is missing" do
      message = %Message{
        id: "msg-1",
        payload: "data",
        routing_key: :order_created,
        timestamp: DateTime.utc_now(),
        headers: %{}
      }

      ctx = %Context{
        assigns: %{},
        metadata: %{},
        request: message,
        routing_key: :ming_produce_message,
        timeout: :infinity
      }

      result = ApplyPublicationDefaults.before_handle(ctx)

      assert Context.halted?(result)
      assert Context.response(result) == {:error, :invalid_params}
    end
  end
end
