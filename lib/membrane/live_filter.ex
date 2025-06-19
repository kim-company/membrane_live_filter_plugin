defmodule Membrane.LiveFilter do
  use Membrane.Filter, flow_control_hints?: false
  alias Membrane.Buffer

  require Membrane.Logger

  def_input_pad(:input,
    accepted_format: _any,
    availability: :always
  )

  def_output_pad(:output,
    accepted_format: _any,
    availability: :always,
    flow_control: :push
  )

  def_options(
    safety_delay: [
      spec: Membrane.Time.t(),
      description: """
        Safety buffer of time which increases the delay of the relay but ensures
        that once it starts buffers are emitted at the expected pace.
      """,
      default: Membrane.Time.milliseconds(5)
    ],
    delay: [
      spec: Membrane.Time.t(),
      description: "Tunable sending delay, added to the safety delay",
      default: 0
    ],
    drop_late_buffers?: [
      spec: boolean(),
      description: "When enabled, the filter will drop late packets",
      default: true
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    {[],
     %{
       # options
       safety_delay: opts.safety_delay,
       delay: opts.delay,
       drop_late_buffers?: opts.drop_late_buffers?,
       # runtime
       absolute_time: nil,
       playback: nil,
       closed: false,
       ref_to_buf: %{},
       ref_to_timer: %{}
     }}
  end

  @impl true
  def handle_stream_format(:input, format, _ctx, state) do
    {[stream_format: {:output, format}], state}
  end

  @impl true
  def handle_buffer(pad, buffer, ctx, state = %{playback: nil}) do
    handle_buffer(pad, buffer, ctx, %{
      state
      | playback: Buffer.get_dts_or_pts(buffer) - state.delay
    })
  end

  def handle_buffer(pad, buffer, ctx, state = %{absolute_time: nil}) do
    Membrane.Logger.warning("Absolute time was not set with start notification")
    handle_buffer(pad, buffer, ctx, set_absolute_time(state))
  end

  def handle_buffer(_pad, buffer, _ctx, state) do
    interval = Buffer.get_dts_or_pts(buffer) - state.playback
    send_at = state.absolute_time + interval
    actual_interval = send_at - Membrane.Time.monotonic_time()

    pretty_interval = "#{Float.round(-actual_interval / 1.0e9, 3)}s"

    if send_at == state.absolute_time do
      Membrane.Logger.warning(
        "Buffer with same dts/pts value received: #{Buffer.get_dts_or_pts(buffer)}."
      )
    end

    state =
      state
      |> put_in([:playback], Buffer.get_dts_or_pts(buffer))
      |> put_in([:absolute_time], send_at)

    cond do
      actual_interval < 0 and state.drop_late_buffers? ->
        Membrane.Logger.warning("Late buffer received (#{pretty_interval}): dropping")

        {[], state}

      actual_interval < 0 ->
        Membrane.Logger.warning("Late buffer received (#{pretty_interval}): forwarding")

        flush(buffer, state)

      true ->
        ref = make_ref()

        timer_ref =
          Process.send_after(
            self(),
            {:out, ref},
            :erlang.convert_time_unit(send_at, :nanosecond, :millisecond),
            abs: true
          )

        state =
          state
          |> put_in([:ref_to_buf, ref], buffer)
          |> put_in([:ref_to_timer, ref], timer_ref)

        {[], state}
    end
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    state = %{state | closed: true}
    actions = if map_size(state.ref_to_timer) == 0, do: [end_of_stream: :output], else: []
    {actions, state}
  end

  @impl true
  def handle_info({:out, ref}, _ctx, state) do
    buf = Map.get(state.ref_to_buf, ref)

    state =
      state
      |> update_in([:ref_to_buf], &Map.delete(&1, ref))
      |> update_in([:ref_to_timer], &Map.delete(&1, ref))

    done? = state.closed and map_size(state.ref_to_timer) == 0

    cond do
      is_nil(buf) and done? ->
        # Weird, but OK.
        {[end_of_stream: :output], state}

      is_nil(buf) ->
        {[], state}

      done? ->
        {[buffer: {:output, buf}, end_of_stream: :output], state}

      true ->
        {[buffer: {:output, buf}], state}
    end
  end

  @impl true
  def handle_parent_notification(:set_absolute_time, _ctx, state) do
    {[], set_absolute_time(state)}
  end

  def handle_parent_notification({:delay, delay}, _ctx, state) do
    Membrane.Logger.info("Delay updated: #{state.delay} -> #{delay}")

    state =
      state
      |> update_in([:playback], fn
        nil -> nil
        # undo the previously applied delay before adding the new one
        previous -> previous + state.delay - delay
      end)
      |> put_in([:delay], delay)

    {[], state}
  end

  defp set_absolute_time(state) do
    t = Membrane.Time.monotonic_time() + state.safety_delay

    Membrane.Logger.info(
      "Absolute time set. Emitting buffers in #{Float.round(state.safety_delay / 1.0e9, 3)}s"
    )

    %{state | absolute_time: t}
  end

  defp flush(buffer, state) do
    # First delete every timer
    state.ref_to_timer
    |> Enum.each(fn {_ref, x} -> Process.cancel_timer(x) end)

    # Find every buffer
    buffers =
      state.ref_to_buf
      |> Enum.map(fn {_ref, buffer} -> buffer end)
      |> Enum.sort(fn left, right ->
        Buffer.get_dts_or_pts(left) < Buffer.get_dts_or_pts(right)
      end)

    # Reset the state.
    state =
      state
      |> put_in([:ref_to_buf], %{})
      |> put_in([:ref_to_timer], %{})

    {[buffer: {:output, buffers ++ [buffer]}], state}
  end
end
