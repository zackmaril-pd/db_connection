defmodule DBConnection.Ownership do
  @moduledoc """
  A `DBConnection.Pool` that requires explicit checkout and checking
  as a mechanism to coordinate between processes.

  ### Options

    * `:ownership_pool` - The actual pool to use to power the ownership
      mechanism. The pool is started when the ownership pool is started,
      although this option may also be given on `ownership_checkout/2`
      allowing developers to customize the pool checkout/checkin
    * `:ownership_mode` - When mode is `:manual`, all connections must
      be explicitly checked out before by using `ownership_checkout/2`.
      Otherwise, mode is `:auto` and connections are checked out
      implicitly. In both cases, checkins are implicit via
      `ownership_checkin/2`. Defaults to `:auto`.

  Furthermore, if the `:ownership_pool` has an atom name given in
  the `:name` option, an ETS table will be created and automatically
  used for lookups whenever the name is used on checkout.
  """

  @behaviour DBConnection.Pool

  alias DBConnection.Ownership.Manager
  alias DBConnection.Ownership.Owner

  ## Ownership API

  @doc """
  Explicitly checks a connection out from the ownership manager.

  It may return `:ok` if the connection is checked out.
  `{:already, :owner | :allowed}` if the caller process already
  has a connection, `:error` if it could be not checked out or
  raise if there was an error.
  """
  @spec ownership_checkout(GenServer.server, Keyword.t) ::
    :ok | {:already, :owner | :allowed} | :error | no_return
  def ownership_checkout(manager, opts) do
     case Manager.checkout(manager, opts) do
      {:init, owner} -> Owner.init(owner, opts)
      {:already, _} = already -> already
    end
  end

  @doc """
  Changes the ownwership mode.

  `mode` may be `:auto` or `:manual`. Returns `:ok`.
  """
  @spec ownership_mode(GenServer.server, :auto | :manual, Keyword.t) ::
    :ok
  defdelegate ownership_mode(manager, mode, opts), to: Manager, as: :mode

  @doc """
  Checks a connection back in.

  A connection can only be checked back in by its owner.
  """
  @spec ownership_checkin(GenServer.server, Keyword.t) ::
    :ok | :not_owner | :not_found
  defdelegate ownership_checkin(manager, opts), to: Manager, as: :checkin

  @doc """
  Allows the process given by `allow` to use the connection checked out by `owner`.

  It may return `:ok` if the connection is checked out.
  `{:already, :owner | :allowed}` if the `allow` process already
  has a connection, `:not_owner` if the owner process is not an
  owner or `:not_found` if the owner process does not have any
  connection checked out.
  """
  @spec ownership_allow(GenServer.server, owner :: pid, allow :: pid, Keyword.t) ::
    :ok | {:already, :owner | :allowed} | :not_owner | :not_found
  defdelegate ownership_allow(manager, owner, allow, opts), to: Manager, as: :allow

  ## Pool callbacks

  @doc false
  def start_link(module, opts) do
    Manager.start_link(module, opts)
  end

  @doc false
  def child_spec(module, opts, child_opts) do
    Supervisor.Spec.worker(Manager, [module, opts], child_opts)
  end

  @doc false
  def checkout(manager, opts) do
    case Manager.lookup(manager, opts) do
      {:init, owner} ->
        case Owner.init(owner, opts) do
          :ok -> Owner.checkout(owner, opts)
          :error -> :error
        end
      {:ok, owner} ->
        Owner.checkout(owner, opts)
      :not_found ->
        raise "cannot find ownership process for #{inspect self()}. " <>
              "This may happen if you have not explicitly checked out or " <>
              "the checked out process crashed"
    end
  end

  @doc false
  def checkin(owner, state, opts) do
    Owner.checkin(owner, state, opts)
  end

  @doc false
  def disconnect(owner, exception, state, opts) do
    Owner.disconnect(owner, exception, state, opts)
  end

  @doc false
  def stop(owner, reason, state, opts) do
    Owner.stop(owner, reason, state, opts)
  end
end