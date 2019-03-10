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
  use Receiver, test: true

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
