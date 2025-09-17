defmodule Ming do
  @moduledoc """
  Ming - A lightweight, extensible CQRS/ES framework for Elixir.

  Ming provides a comprehensive framework for building Command Query Responsibility Segregation (CQRS)
  and Event Sourcing (ES) applications in Elixir. It offers a modular architecture with clear separation
  of concerns for commands, events, and queries.

  ## Key Features
  - **Command Processing**: Robust command handling with middleware support
  - **Event Publishing**: Concurrent event processing with configurable concurrency controls
  - **Routing System**: Flexible routing for both commands and events
  - **Middleware Pipeline**: Extensible middleware system for cross-cutting concerns
  - **Telemetry Integration**: Comprehensive monitoring and metrics
  - **Concurrency Control**: Configurable parallel processing for high-throughput scenarios

  ## Architecture Overview
  Ming follows a layered architecture:

  1. **Command Processor** (`Ming.CommandProcessor`) - Top-level command handling
  2. **Composite Routers** (`Ming.CompositeRouter`) - Aggregate multiple routers
  3. **Individual Routers** (`Ming.Router`) - Unified command and event routing
  4. **Send/Publish Routers** (`Ming.SendRouter`, `Ming.PublishRouter`) - Specialized routing
  5. **Dispatcher** (`Ming.Dispatcher`) - Core dispatching mechanism
  6. **Execution Context** (`Ming.ExecutionContext`) - Command execution context
  7. **Pipeline** (`Ming.Pipeline`) - Middleware pipeline management

  ## Getting Started

  ### Installation
  Add Ming to your `mix.exs`:

      defp deps do
        [
          {:ming, "~> 0.1.0"}
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
  - `Ming.Router` - Unified command and event routing
  - `Ming.SendRouter` - Command sending infrastructure
  - `Ming.PublishRouter` - Event publishing infrastructure

  ### Support Modules
  - `Ming.Dispatcher` - Core dispatching mechanism
  - `Ming.ExecutionContext` - Command execution context
  - `Ming.Pipeline` - Middleware pipeline management
  - `Ming.ExecutionResult` - Execution result encapsulation
  - `Ming.Middleware` - Middleware behavior definition

  ### Infrastructure
  - `Ming.TaskSupervisor` - Task supervision for async operations
  - `Ming.Telemetry` - Telemetry and monitoring integration

  ## Configuration
  Ming can be configured in your `config/config.exs`:

      config :ming,
        default_timeout: 15_000,
        max_concurrency: 4,
        task_supervisor: MyApp.TaskSupervisor

  ## Telemetry
  Ming emits telemetry events for monitoring:
  - `[:ming, :command, :start]` - Command processing started
  - `[:ming, :command, :stop]` - Command processing completed
  - `[:ming, :command, :exception]` - Command processing error
  - `[:ming, :event, :publish]` - Event publication
  - `[:ming, :dispatch, :start]` - Dispatch started
  - `[:ming, :dispatch, :stop]` - Dispatch completed

  ## Example

      # Define a command
      defmodule CreateUser do
        defstruct [:name, :email, :password]
      end


      # Define a handler
      defmodule UserHandler do
        def execute(%CreateUser{} = command) do
          # Business logic here
          {:ok, [%UserCreated{id: UUID.generate(), name: command.name, email: command.email}]}
        end
      end

      # Send the command
      MyApp.CommandProcessor.send(%CreateUser{
        name: "John Doe",
        email: "john@example.com",
        password: "secret"
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
