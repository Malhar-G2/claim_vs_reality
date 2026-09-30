require "test_helper"
require "openai_batch/jsonl_batch_file_writer"

class OpenaiBatch::JsonlBatchFileWriterTest < Minitest::Test
  def test_write_persists_one_json_object_per_line
    path = OpenaiBatch::JsonlBatchFileWriter.new.write(
      requests: [
        { custom_id: "one", method: "POST", url: "/v1/responses", body: { model: "gpt-4.1" } },
        { custom_id: "two", method: "POST", url: "/v1/responses", body: { model: "gpt-4.1" } }
      ]
    )

    lines = File.readlines(path, chomp: true)

    assert_equal 2, lines.length
    assert_equal "one", JSON.parse(lines.first).fetch("custom_id")
  end
end
