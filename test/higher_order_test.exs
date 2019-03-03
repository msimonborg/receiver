defmodule Worker do
  def perform_complex_work(val, fun) do
    val
    |> do_some_work()
    |> fun.()
    |> do_other_work()
  end

  def do_some_work(val), do: :math.log(val)

  def do_other_work(val), do: :math.exp(val) |> :math.floor()
end

defmodule ExUnit.HigherOrderTest do
  use ExUnit.Case
  use Receiver, test: true

  setup do
    start_receiver(fn -> nil end)
    :ok
  end

  def register(x) do
    get_and_update_receiver(fn _ -> {x, x} end)
  end

  test "it does the work in stages with help from an anonymous function" do
    assert get_receiver() == nil

    result = Worker.perform_complex_work(1.0, fn x -> register(x) end)
    receiver = get_receiver()

    assert Worker.do_some_work(1.0) == receiver
    assert Worker.do_other_work(receiver) == result
  end
end
