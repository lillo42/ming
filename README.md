# Ming
Ming is a library focus on CQRS pattern, it's heavily inspired in [Brigther](https://github.com/BrighterCommand/Brighter) C# Framework and [Commanded](https://github.com/commanded/commanded/) elixir library

Provides support for:
- Command registration and dispatch.
- Events registration and dispatch (the current implementation will run it in only one machine).
- 
Requires Erlang/OTP v271.0 and Elixir v1.18 or later.

## Installation

Add :ming to the list of dependencies in mix.exs:

```elixir
def deps do
  [
    {:ming, "~> 0.1.0"}
  ]
end
```

Used in production?
Not yet, it's a small project and still on-going developing

## Contributing
Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/christopheradams/elixir_style_guide).

You should include unit tests to cover any changes. Run mix test to execute the test suite.
