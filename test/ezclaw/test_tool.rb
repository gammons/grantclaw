# frozen_string_literal: true

require_relative "../test_helper"

# Define a test tool inline
class GreetTool < Ezclaw::Tool
  desc "Greet a person by name"
  param :name, type: :string, desc: "Person's name", required: true
  param :style, type: :string, enum: %w[formal casual], default: "casual"

  def call(name:, style: "casual")
    if style == "formal"
      "Good day, #{name}."
    else
      "Hey #{name}!"
    end
  end
end

class TestTool < Minitest::Test
  def test_tool_description
    assert_equal "Greet a person by name", GreetTool.tool_description
  end

  def test_tool_params
    params = GreetTool.tool_params
    assert_equal 2, params.length
    assert_equal :name, params[0][:name]
    assert_equal true, params[0][:required]
    assert_equal :style, params[1][:name]
    assert_equal %w[formal casual], params[1][:enum]
  end

  def test_json_schema
    schema = GreetTool.json_schema
    assert_equal "greet", schema[:name]
    assert_equal "Greet a person by name", schema[:description]
    props = schema[:parameters][:properties]
    assert_includes props.keys, "name"
    assert_includes props.keys, "style"
    assert_equal %w[name], schema[:parameters][:required]
  end

  def test_call
    tool = GreetTool.new
    assert_equal "Hey Grant!", tool.call(name: "Grant")
    assert_equal "Good day, Grant.", tool.call(name: "Grant", style: "formal")
  end

  def test_tool_name_derived_from_class
    assert_equal "greet", GreetTool.tool_name
  end

  def test_execute_catches_errors
    bad_tool_class = Class.new(Ezclaw::Tool) do
      desc "broken"
      def call
        raise "boom"
      end
    end
    result = bad_tool_class.new.execute({})
    assert_includes result, "Error"
    assert_includes result, "boom"
  end

  # Regression: re-declaring the same param (e.g. when a file gets
  # re-loaded and the class body re-runs) must not accumulate duplicate
  # entries. Previously this produced schemas with
  # `required: ["action", "action"]`, which ZAI rejects with HTTP 400
  # code 1210 ("Invalid API parameter").
  def test_param_redeclaration_replaces_instead_of_appending
    dup_class = Class.new(Ezclaw::Tool) do
      desc "dup test"
      param :action, type: :string, enum: %w[a b], required: true
      # Simulate the class body re-running (which is what an accidental
      # file reload does):
      param :action, type: :string, enum: %w[a b], required: true
      param :other, type: :string
    end

    # Exactly two params, action and other (not three).
    assert_equal 2, dup_class.tool_params.length
    assert_equal [:action, :other], dup_class.tool_params.map { |p| p[:name] }

    # Required array has exactly one "action".
    schema = dup_class.json_schema
    assert_equal ["action"], schema[:parameters][:required]
  end

  # Belt-and-suspenders: even if duplicates somehow land in @params,
  # the emitted schema must have a unique required array.
  def test_json_schema_required_is_always_unique
    dup_class = Class.new(Ezclaw::Tool) do
      desc "dup schema"
      param :action, required: true
    end
    # Inject a synthetic duplicate (bypassing the param helper)
    dup_class.instance_variable_get(:@params) <<
      { name: :action, type: :string, desc: nil, enum: nil, required: true, default: nil }
    assert_equal 2, dup_class.tool_params.length

    schema = dup_class.json_schema
    assert_equal ["action"], schema[:parameters][:required]
  end
end
