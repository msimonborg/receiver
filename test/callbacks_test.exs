defmodule ExUnit.CallbacksTest do
  use ExUnit.Case
  use ExUnitProperties

  defmodule Consumer do
    use Receiver, as: :consumer

    def start, do: start_consumer()
    def get, do: get_consumer()
    def put(val), do: update_consumer(fn _ -> val end)
    def stop, do: stop_consumer()
  end

  defmodule Producer do
    use Receiver, as: :producer

    def start(val), do: start_producer(fn -> val end)
    def stop(reason \\ :normal), do: stop_producer(reason)
    def get, do: get_producer()
    def update(val), do: update_producer(fn _ -> val end)
    def get_and_update(val), do: get_and_update_producer(fn old -> {old, val} end)

    def handle_start(:producer, pid, state), do: Consumer.put({pid, state})
    def handle_stop(:producer, reason, state), do: Consumer.put({reason, state})

    def handle_get(:producer, return) when is_atom(return) do
      Consumer.put(return)
      {:reply, :check_with_consumer}
    end

    def handle_get(:producer, return) when is_binary(return) do
      Consumer.put(:check_with_producer)
      {:reply, return}
    end

    def handle_get(:producer, return) when is_integer(return), do: return

    def handle_update(:producer, old, new), do: Consumer.put({old, new})

    def handle_get_and_update(:producer, return_value, state) when return_value == state do
      state
    end

    def handle_get_and_update(:producer, return_value, state) do
      Consumer.put(return_value)
      {:reply, {return_value, state}}
    end
  end

  setup_all do
    Consumer.start()
    on_exit(fn -> Consumer.stop() end)
  end

  property "invokes the handle_start/3 callback passing the pid and state" do
    check all state <- term() do
      {:ok, pid} = Producer.start(state)
      assert Consumer.get() == {pid, state}
      :ok = Producer.stop()
    end
  end

  property "invokes the handle_stop/3 callback passing the reason and state" do
    check all state <- term() do
      {:ok, _} = Producer.start(state)
      :ok = Producer.stop()
      assert Consumer.get() == {:normal, state}
    end
  end

  property "invokes the handle_get/2 callback passing the state and returning a reply" do
    check all state <- atom(:alphanumeric) do
      {:ok, _} = Producer.start(state)
      assert Producer.get() == :check_with_consumer
      assert Consumer.get() == state
      :ok = Producer.stop()
    end

    check all state <- string(:ascii) do
      {:ok, _} = Producer.start(state)
      assert Producer.get() == state
      assert Consumer.get() == :check_with_producer
      :ok = Producer.stop()
    end
  end

  property "raises a Receiver.CallbackError when handle_get/2 does not return {:reply, reply}" do
    check all state <- integer() do
      {:ok, _} = Producer.start(state)

      assert_raise(Receiver.CallbackError, ~r{handle_get/2 must have a return in the form:}, fn ->
        Producer.get()
      end)

      :ok = Producer.stop()
    end
  end

  property "invokes the handle_update/3 callback passing the old state and new state" do
    check all old <- term(),
              new <- term() do
      {:ok, _} = Producer.start(old)

      assert :ok = Producer.update(new)
      assert Consumer.get() == {old, new}

      :ok = Producer.stop()
    end
  end

  property "invokes handle_get_and_update/3 passing the return_value and the new state" do
    check all old <- term(),
              new <- term(),
              old != new do
      {:ok, _} = Producer.start(old)

      assert Producer.get_and_update(new) == {old, new}
      assert Consumer.get() == old

      :ok = Producer.stop()
    end
  end

  property "raises a Receiver.CallbackError when handle_get_and_update/3 does not return {:reply, reply}" do
    check all val <- term() do
      {:ok, _} = Producer.start(val)

      assert_raise(
        Receiver.CallbackError,
        ~r{handle_get_and_update/3 must have a return in the form:},
        fn ->
          Producer.get_and_update(val)
        end
      )

      :ok = Producer.stop()
    end
  end
end
