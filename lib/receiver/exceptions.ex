defmodule Receiver.NotFoundError do
  defexception message: "receiver not found"
end

defmodule Receiver.CallbackError do
  defexception message: "callback error"
end
