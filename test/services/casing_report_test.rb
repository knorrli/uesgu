require_relative "../db_test_helper"

class CasingReportTest < ActiveSupport::TestCase
  def report_for
    io = StringIO.new
    CasingReport.call(io)
    io.string
  end

  test "counts what would change, what is left alone, and the whole corpus" do
    event(title: "MICHAEL SCHENKER GROUP", data_source: "Zorpsaal")
    event(title: "KMFDM", data_source: "Zorpsaal")
    event(title: "Curtis Harding", data_source: "Zorpsaal")

    line = report_for[/^titles.*$/]

    assert_match(/3 values/, line)
    assert_match(/2 shouted/, line)
    assert_match(/1 left alone/, line)
    assert_match(/1 would recase/, line)
  end

  test "lists each change with its source and its outcome" do
    event(title: "MICHAEL SCHENKER GROUP", data_source: "Zorpsaal")

    assert_match(/\[Zorpsaal\] MICHAEL SCHENKER GROUP → Michael Schenker Group/, report_for)
  end

  test "breaks the counts down by source" do
    event(title: "MICHAEL SCHENKER GROUP", data_source: "Zorpsaal")
    event(title: "CORY WONG", data_source: "Flarnhalle")

    report = report_for

    assert_match(/Zorpsaal\s+1 shouted\s+1 would recase/, report)
    assert_match(/Flarnhalle\s+1 shouted\s+1 would recase/, report)
  end

  test "reports descriptions and names alongside titles" do
    event(title: "Curtis Harding", description: "EIN ABEND MIT FREUNDEN")

    report = report_for

    assert_match(/^descriptions.*1 would recase/, report)
    assert_match(/EIN ABEND MIT FREUNDEN → Ein Abend Mit Freunden/, report)
    assert_match(/^places/, report)
    assert_match(/^localities/, report)
  end

  # The heading, not the tally on the summary line above it, which always reads
  # "0 would recase" here.
  test "prints no listing under a section that has no changes" do
    event(title: "Curtis Harding")

    assert_no_match(/^  would recase$/, report_for[/^titles.*?(?=^descriptions)/m])
  end
end
