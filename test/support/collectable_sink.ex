defmodule Support.CollectableSink do
  use Membrane.Sink

  def_input_pad(:input,
    accepted_format: _any,
    availability: :always
  )

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{acc: []}}
  end

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    {[],
     update_in(state, [:acc], fn acc -> [%{time: DateTime.utc_now(), pts: buffer.pts} | acc] end)}
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    {[notify_parent: {:delays, delays(state.acc)}], state}
  end

  @doc """
  Returns the delays of each received payload starting from the moment the relay
  was initialized.
  """
  def delays(acc) do
    acc
    |> Enum.reduce([], fn
      %{time: next, pts: pts}, [] ->
        [%{time: next, pts: pts, actual_diff: 0, expected_diff: 0, delta: 0}]

      %{time: time, pts: pts}, acc = [%{time: prev_time, pts: prev_pts} | _] ->
        actual_diff = DateTime.diff(time, prev_time, :millisecond)
        expected_diff = Membrane.Time.as_milliseconds(pts - prev_pts, :round)
        delta = abs(actual_diff - expected_diff)

        [
          %{
            time: time,
            pts: pts,
            actual_diff: actual_diff,
            expected_diff: expected_diff,
            delta: delta
          }
          | acc
        ]
    end)
    |> Enum.reverse()
  end
end
