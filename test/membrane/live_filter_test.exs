defmodule Membrane.LiveFilterTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.{Buffer, LiveFilter, Testing, Time}

  defp assert_delays(pipeline) do
    assert_pipeline_notified(pipeline, :sink, {:delays, delays})

    delays
    |> Enum.each(fn %{delta: delta} ->
      assert delta <= 10, "delays are not realtime: #{inspect(delays)}"
    end)

    Testing.Pipeline.terminate(pipeline, blocking?: true)
  end

  test "Limits playback speed to realtime" do
    buffers = [
      %Buffer{pts: 0, payload: 0},
      %Buffer{pts: Time.milliseconds(10), payload: 1}
    ]

    structure = [
      child(:src, %Testing.Source{output: Testing.Source.output_from_buffers(buffers)})
      |> child(:realtimer, LiveFilter)
      |> child(:sink, Support.CollectableSink)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(structure: structure)
    assert_delays(pipeline)
  end

  test "Start following the time of the first buffer" do
    buffers = [
      %Buffer{pts: Time.milliseconds(100), payload: 0}
    ]

    structure = [
      child(:src, %Testing.Source{output: Testing.Source.output_from_buffers(buffers)})
      |> child(:realtimer, LiveFilter)
      |> child(:sink, Testing.Sink)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(structure: structure)
    assert_sink_buffer(pipeline, :sink, %Buffer{payload: 0}, 20)
    assert_end_of_stream(pipeline, :sink)
    Testing.Pipeline.terminate(pipeline, blocking?: true)
  end

  test "Respects configured delay" do
    buffers = [
      %Buffer{pts: Time.milliseconds(0), payload: 0}
    ]

    structure = [
      child(:src, %Testing.Source{output: Testing.Source.output_from_buffers(buffers)})
      |> child(:realtimer, %LiveFilter{delay: Time.milliseconds(100)})
      |> child(:sink, Testing.Sink)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(structure: structure)

    refute_sink_buffer(pipeline, :sink, _buffer, 90)
    assert_sink_buffer(pipeline, :sink, %Buffer{payload: 0}, 20)
    Testing.Pipeline.terminate(pipeline, blocking?: true)
  end

  test "Limits playback speed to realtime when a delay is configured" do
    buffers = [
      %Buffer{pts: 0, payload: 0},
      %Buffer{pts: Time.milliseconds(10), payload: 1},
      %Buffer{pts: Time.milliseconds(20), payload: 2}
    ]

    structure = [
      child(:src, %Testing.Source{output: Testing.Source.output_from_buffers(buffers)})
      |> child(:realtimer, %LiveFilter{delay: Membrane.Time.milliseconds(100)})
      |> child(:sink, Support.CollectableSink)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(structure: structure)
    assert_delays(pipeline)
  end
end
