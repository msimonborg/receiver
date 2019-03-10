defmodule ExUnitReceiver do
  @moduledoc """
  Using a receiver in your test cases.

  A `Receiver` can be used to test higher order functions by using `ExUnitReceiver` in an `ExUnit` test case.
  Consider the following example:

      defmodule Worker do
        def perform_complex_work(val, fun) do
          val
          |> do_some_work()
          |> fun.()
          |> do_other_work()
        end

        def do_some_work(val), do: val |> :math.log() |> round()

        def do_other_work(val), do: val |> :math.exp() |> round()
      end

      defmodule ExUnit.HigherOrderTest do
        use ExUnit.Case
        use ExUnitProperties
        use ExUnitReceiver

        setup do
          start_receiver(fn -> nil end)
          :ok
        end

        def register(x) do
          get_and_update_receiver(fn _ -> {x, x} end)
        end

        property "it does the work in stages with help from an anonymous function" do
          check all int <- positive_integer() do
            result = Worker.perform_complex_work(int, fn x -> register(x) end)
            receiver = get_receiver()

            assert Worker.do_some_work(int) == receiver
            assert Worker.do_other_work(receiver) == result
          end
        end
      end

  When you call the `start_receiver` functions within a `setup` block, it delegates to
  `ExUnit.Callbacks.start_supervised/2`. This will start the receiver as a supervised process under
  the test supervisor, automatically starting and shutting it down between tests to clean up state.
  This can help you test that your higher order functions are executing with the correct arguments
  and returning the expected results.
  """

  defmacro __using__(opts) do
    quote do
      use Receiver, unquote(Keyword.merge(opts, test: true))
    end
  end
end
