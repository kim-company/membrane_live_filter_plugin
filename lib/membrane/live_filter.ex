defmodule Membrane.LiveFilter do
  use Membrane.Filter

  require Membrane.Logger

  def_input_pad(:input,
    accepted_format: _,
    availability: :always
  )

  def_output_pad(:output,
    accepted_format: _,
    availability: :always,
    mode: :push
  )

  def_options(
    safety_delay: [
      spec: Membrane.Time.t(),
      description: """
        Safety buffer of time which increases the delay of the relay but ensures
        that once it starts buffers are emitted at the expected pace
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
       absolute_time: nil,
       playback: nil,
       safety_delay: opts.safety_delay,
       delay: opts.delay,
       drop_late_buffers?: opts.drop_late_buffers?,
       timers: 0,
       closed: false
     }}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[demand: {:input, 1}], state}
  end

  @impl true
  def handle_stream_format(:input, format, _ctx, state) do
    {[stream_format: {:output, format}], state}
  end

  @impl true
  def handle_process(pad, buffer, ctx, state = %{playback: nil}) do
    handle_process(pad, buffer, ctx, %{state | playback: buffer.pts - state.delay})
  end

  def handle_process(pad, buffer, ctx, state = %{absolute_time: nil}) do
    Membrane.Logger.warn("Absolute time was not set with start notification")
    t = Membrane.Time.monotonic_time() + state.safety_delay
    handle_process(pad, buffer, ctx, %{state | absolute_time: t})
  end

  def handle_process(_pad, buffer, _ctx, state) do
    interval = buffer.pts - state.playback
    send_at = state.absolute_time + interval
    actual_interval = send_at - Membrane.Time.monotonic_time()

    state = %{state | playback: buffer.pts, absolute_time: send_at}

    if actual_interval < 0 do
      Membrane.Logger.warn(
        "Late buffer received. It came #{Membrane.Time.pretty_duration(actual_interval)} too late",
        %{
          interval: actual_interval,
          pts: buffer.pts,
          dropped: state.drop_late_buffers?
        }
      )

      if !state.drop_late_buffers? do
        {[buffer: {:output, buffer}, demand: {:input, 1}], state}
      else
        {[demand: {:input, 1}], state}
      end
    else
      # Membrane.Logger.debug(
      #   "Scheduled buffer with pts #{Membrane.Time.pretty_duration(buffer.pts)} to be sent in #{Membrane.Time.pretty_duration(actual_interval)}"
      # )

      Process.send_after(
        self(),
        {:buffer, buffer},
        :erlang.convert_time_unit(send_at, :nanosecond, :millisecond),
        abs: true
      )

      {[], update_in(state, [:timers], fn count -> count + 1 end)}
    end
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    state = %{state | closed: true}
    actions = if state.timers <= 0, do: [end_of_stream: :output], else: []
    {actions, state}
  end

  @impl true
  def handle_info({:buffer, buffer}, _ctx, state) do
    {count, state} =
      get_and_update_in(state, [:timers], fn count ->
        count = count - 1
        {count, count}
      end)

    actions =
      List.flatten([
        [buffer: {:output, buffer}],
        if(count == 0 and state.closed, do: [end_of_stream: :output], else: [demand: {:input, 1}])
      ])

    {actions, state}
  end

  @impl true
  def handle_parent_notification(:start, _ctx, state) do
    t = Membrane.Time.monotonic_time() + state.safety_delay
    {[], %{state | absolute_time: t}}
  end

  def handle_parent_notification({:delay, delay}, _ctx, state) do
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
end
