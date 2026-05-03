defmodule DurableServer.TestHelper do
  @moduledoc """
  Test helpers for DurableServer tests.
  """

  import ExUnit.Assertions

  alias DurableServer.ObjectStore

  def assert_raise_message_contains(exception, expected, fun)
      when is_atom(exception) and is_binary(expected) and is_function(fun, 0) do
    error = assert_raise exception, fun
    assert String.contains?(Exception.message(error), expected)
    error
  end

  def assert_raise_message_contains(exception, expected_messages, fun)
      when is_atom(exception) and is_list(expected_messages) and is_function(fun, 0) do
    error = assert_raise exception, fun
    message = Exception.message(error)
    assert Enum.any?(expected_messages, &String.contains?(message, &1))
    error
  end

  @doc """
  Returns the default object store config for testing as a keyword list.
  """
  def test_object_store_opts(opts \\ []) do
    Keyword.merge(
      [
        access_key_id: "test",
        secret_access_key: "test",
        s3_endpoint: "http://localhost:4566",
        iam_endpoint: "http://localhost:4566",
        default_region: "us-east-1",
        bucket: "durable-test-bucket"
      ],
      opts
    )
  end

  @doc """
  Creates an ObjectStore configured for testing.

  Uses environment variables or defaults suitable for LocalStack.
  """
  def test_object_store(opts \\ []) do
    ObjectStore.new(test_object_store_opts(opts))
  end
end
