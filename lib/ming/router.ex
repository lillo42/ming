defmodule Ming.Router do
  @moduledoc """
  Command routing macro to allow configuration of each command to its command handler.


  ## Example

  Define a router module which uses `Ming.Router` and configures
  available request to dispatch:


      defmodule BankRouter do
        use Ming.Router


        dispatch OpenAccount,
          to: OpenAccountHandler,
      end

  The `to` option determines which module receives the request being dispatched.

  This command handler module must implement a `handle/1` function. It receives
  the command to execute.

  Once configured, you can either dispatch a request by using the module and

  specifying the application:

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankRouter.send(command, application: BankApp)


  Or, more simply, you should include the router module in your application:

      defmodule CommandProcssor do
        use Ming.CommandProcssor , otp_app: :my_app

        router MyApp.Router
      end

  Then dispatch commands using the app:

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankApp.send(command)

  Alternatively, you may specify the name of a function on your handle module to which the command will be dispatched:

  ### Example

      defmodule BankRouter do
        use Commanded.Commands.Router


        # Will route to `BankAccount.open_account/2`
        dispatch OpenAccount, to: BankAccount, function: :open_account 
      end


  ## Metadata

  You can associate metadata with all events created by the command.

  Supply a map containing key/value pairs comprising the metadata:

      :ok = BankApp.send(command, metadata: %{"ip_address" => "127.0.0.1"})

  """
end
