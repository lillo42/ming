defmodule Ming do
  @moduledoc """
  Ming - A lightweight, extensible CQRS/ES framework for Elixir.

  Ming provides a comprehensive framework for building Command Query Responsibility Segregation (CQRS)
  and Event Sourcing (ES) applications in Elixir. It offers a modular architecture with clear separation
  of concerns for commands, events, and queries.

  ## Key Features
  - **Command Processing**: Robust command handling with middleware support
  - **Event Publishing**: Concurrent event processing with configurable concurrency controls
  - **Query Execution**: Read-optimized query routing with middleware support
  - **Routing System**: Flexible routing for commands, events, and queries
  - **Middleware Pipeline**: Extensible middleware system for cross-cutting concerns
  - **Telemetry Integration**: Comprehensive monitoring and metrics
  - **Concurrency Control**: Configurable parallel processing for high-throughput scenarios

  ## Architecture Overview
  Ming follows a layered architecture:

  1. **Command Processor** (`Ming.CommandProcessor`) - Top-level command handling
  2. **Composite Routers** (`Ming.CompositeRouter`, `Ming.SendCompositeRouter`, `Ming.PublishCompositeRouter`, `Ming.QueryCompositeRouter`) - Aggregate multiple routers
  3. **Individual Routers** (`Ming.Router`) - Unified command, event, and query routing
  4. **Send/Publish/Query Routers** (`Ming.SendRouter`, `Ming.PublishRouter`, `Ming.QueryRouter`) - Specialized routing
  5. **Dispatcher** (`Ming.Dispatcher`) - Core dispatching mechanism
  6. **Execution Context** (`Ming.ExecutionContext`) - Command execution context
  7. **Pipeline** (`Ming.Pipeline`) - Middleware pipeline management

  ## Getting Started

  ### Installation
  Add Ming to your `mix.exs`:

      defp deps do
        [
          {:ming, "~> 0.1.2"}
        ]
      end

  ### Basic Usage
  1. Create a command processor:

      defmodule MyApp.CommandProcessor do
        use Ming.CommandProcessor,
          otp_app: :my_app,
          max_concurrency: 4,
          dispatch_opts: [timeout: 15_000]

        router MyApp.Accounting.Router
        router MyApp.Inventory.Router
      end

  2. Create domain routers:

      defmodule MyApp.Accounting.Router do
        use Ming.Router,
          ming: :my_app

        middleware MyApp.AuthMiddleware
        middleware MyApp.LoggingMiddleware

        dispatch CreateInvoice, to: AccountingHandler
        dispatch PaymentProcessed, to: AccountingHandler
      end

  3. Send commands:

      MyApp.CommandProcessor.send(%CreateInvoice{amount: 100.0, customer_id: 123})

  ## Modules Overview
  ### Core Modules
  - `Ming.CommandProcessor` - Top-level command processing interface
  - `Ming.CompositeRouter` - Aggregation of multiple routers
  - `Ming.Router` - Unified command, event, and query routing
  - `Ming.SendRouter` - Command sending infrastructure
  - `Ming.PublishRouter` - Event publishing infrastructure
  - `Ming.QueryRouter` - Query execution infrastructure

  ### Support Modules
  - `Ming.Dispatcher` - Core dispatching mechanism
  - `Ming.ExecutionContext` - Command execution context
  - `Ming.Pipeline` - Middleware pipeline management
  - `Ming.ExecutionResult` - Execution result encapsulation
  - `Ming.Middleware` - Middleware behavior definition

  ### Infrastructure
  - `Ming.TaskSupervisor` - Task supervision for async operations
  - `Ming.Telemetry` - Telemetry and monitoring integration

  ## Telemetry
  Ming emits telemetry events for monitoring:

  ### Dispatch telemetry
  - `[:ming, :application, :dispatch, :start]` - Dispatch started
  - `[:ming, :application, :dispatch, :stop]` - Dispatch completed

  Metadata includes:
  - `:application` - The OTP application name
  - `:execution_context` - The `Ming.ExecutionContext` struct
  - `:dispatcher_type` - `:command`, `:event`, `:query`, or `:unknown`
  - `:error` - Present only on stop events when dispatch fails

  ### Handler telemetry
  - `[:ming, :handler, :execute, :start]` - Handler execution started
  - `[:ming, :handler, :execute, :stop]` - Handler execution completed
  - `[:ming, :handler, :execute, :exception]` - Handler raised an exception or threw

  ## Example

      # Define a command
      defmodule CreateUser do
        defstruct [:name, :email]
      end

      # Define a handler
      defmodule UserHandler do
        def execute(%CreateUser{} = command, _context) do
          # Business logic here
          :ok
        end
      end

      # Send the command
      MyApp.CommandProcessor.send(%CreateUser{
        name: "John Doe",
        email: "john@example.com"
      })

  ## Philosophy
  Ming is designed to be:
  - **Modular**: Use only what you need
  - **Extensible**: Easy to add custom middleware and handlers
  - **Performant**: Built for high-throughput scenarios
  - **Observable**: Comprehensive telemetry and logging
  - **Consistent**: Uniform API across all components

  ## License
  Ming is released under the GNU General Public License v3.0.

  ## Support
  - GitHub: https://github.com/lillo42/ming
  - Issues: https://github.com/lillo42/ming/issues
  - Documentation: https://hexdocs.pm/ming

  ## Versioning
  Ming follows Semantic Versioning 2.0.0.
  """
end
