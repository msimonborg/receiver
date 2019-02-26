defmodule Receiver do
  @moduledoc """
  Documentation for Receiver.
  """

  defmacro __using__(opts) do
    {name, opts} = Keyword.pop(opts, :as, :receiver)
    {test, _} = Keyword.pop(opts, :test, false)
    module_name =
      __CALLER__.module
      |> Module.split()
      |> Enum.concat([Atom.to_string(name) |> Macro.camelize()])
      |> Module.concat()

    quote bind_quoted: [name: name, module_name: module_name, test: test] do
      import Receiver

      @receiver_module_name module_name

      quote do: alias(module_name)

      defmodule module_name do
        use Agent

        def start_link(arg)

        def start_link([module, fun, args]) do
          Agent.start_link(module, fun, args, name: __MODULE__)
        end

        def start_link(fun) when is_function(fun) do
          Agent.start_link(fun, name: __MODULE__)
        end

        def start_link(arg) do
          Agent.start_link(fn -> arg end, name: __MODULE__)
        end

        def get do
          Agent.get(__MODULE__, & &1)
        end

        def update(fun) do
          Agent.update(__MODULE__, fun)
        end
      end

      if test do

        def unquote(:"start_#{name}")(args \\ []) do
          start_supervised({@receiver_module_name, args})
        end

        def unquote(:"start_#{name}")(module, fun, args) do
          start_supervised({@receiver_module_name, [module, fun, args]})
        end

      else

        def unquote(:"start_#{name}")(args \\ []) do
          DynamicSupervisor.start_child(Receiver.Supervisor, {@receiver_module_name, args})
        end

        def unquote(:"start_#{name}")(module, fun, args) do
          DynamicSupervisor.start_child(Receiver.Supervisor, {@receiver_module_name, [module, fun, args]})
        end

      end

      def unquote(:"get_#{name}")() do
        @receiver_module_name.get()
      end

      def unquote(:"update_#{name}")(fun) do
        @receiver_module_name.update(fun)
      end
    end
  end
end
