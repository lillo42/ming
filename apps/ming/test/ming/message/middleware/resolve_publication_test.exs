defmodule Ming.Message.Middleware.ResolvePublicationTest do
  use ExUnit.Case

  alias Ming.Context
  alias Ming.Message.Middleware.ResolvePublication

  setup do
    original_env = Application.get_env(:ming, :gateways)

    on_exit(fn ->
      if is_nil(original_env) do
        Application.delete_env(:ming, :gateways)
      else
        Application.put_env(:ming, :gateways, original_env)
      end
    end)
  end

  defp context(routing_key, default_mapper \\ Ming.Message.Mapper.Json) do
    %Context{
      assigns: %{},
      metadata: %{
        message_routing_key: routing_key,
        default_message_mapper: default_mapper
      },
      request: nil,
      routing_key: :ming_produce_message,
      timeout: :infinity
    }
  end

  describe "before_handle/1" do
    test "assigns gateway, publication and mapper when a single publication matches" do
      Application.put_env(:ming, :gateways, [
        [
          adapter: FakeGateway,
          publications: [
            [routing_key: :order_created, mapper: CustomMapper]
          ]
        ]
      ])

      ctx = context(:order_created)
      result = ResolvePublication.before_handle(ctx)

      refute Context.halted?(result)
      assert result.assigns.gateway[:adapter] == FakeGateway
      assert result.assigns.publication[:routing_key] == :order_created
      assert result.assigns.mapper == CustomMapper
    end

    test "falls back to gateway mapper then default mapper" do
      Application.put_env(:ming, :gateways, [
        [
          adapter: FakeGateway,
          mapper: GatewayMapper,
          publications: [[routing_key: :order_created]]
        ]
      ])

      ctx = context(:order_created)
      result = ResolvePublication.before_handle(ctx)

      assert result.assigns.mapper == GatewayMapper
    end

    test "halts when no publication is found" do
      Application.put_env(:ming, :gateways, [])

      ctx = context(:missing_key)
      result = ResolvePublication.before_handle(ctx)

      assert Context.halted?(result)
      assert Context.response(result) == {:error, {:publication_not_found, :missing_key}}
    end

    test "halts when multiple publications match" do
      Application.put_env(:ming, :gateways, [
        [adapter: FakeGateway, publications: [[routing_key: :order_created]]],
        [adapter: FakeGateway, publications: [[routing_key: :order_created]]]
      ])

      ctx = context(:order_created)
      result = ResolvePublication.before_handle(ctx)

      assert Context.halted?(result)
      assert Context.response(result) == {:error, {:multi_publication_found, :order_created, 2}}
    end

    test "reads gateways from the processor module's otp_app" do
      Application.put_env(:fake_otp_app, FakeOtpAppProcessor,
        gateways: [
          [
            adapter: FakeGateway,
            publications: [[routing_key: :order_created]]
          ]
        ]
      )

      on_exit(fn -> Application.delete_env(:fake_otp_app, FakeOtpAppProcessor) end)

      ctx = %Context{
        assigns: %{},
        metadata: %{
          message_routing_key: :order_created,
          default_message_mapper: Ming.Message.Mapper.Json,
          ming_application: FakeOtpAppProcessor
        },
        request: nil,
        routing_key: :ming_produce_message,
        timeout: :infinity
      }

      result = ResolvePublication.before_handle(ctx)

      refute Context.halted?(result)
      assert result.assigns.gateway[:adapter] == FakeGateway
      assert result.assigns.publication[:routing_key] == :order_created
    end

    test "halts when required metadata is missing" do
      ctx = %Context{
        assigns: %{},
        metadata: %{},
        request: nil,
        routing_key: :ming_produce_message,
        timeout: :infinity
      }

      result = ResolvePublication.before_handle(ctx)

      assert Context.halted?(result)
      assert Context.response(result) == {:error, :invalid_context}
    end
  end
end

defmodule FakeGateway do
end

defmodule FakeOtpAppProcessor do
  def __ming_otp_app__, do: :fake_otp_app
end

defmodule CustomMapper do
end

defmodule GatewayMapper do
end
