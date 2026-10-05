///|
test "JSON rejects trailing data and malformed numbers" {
  for input in ["true false", "nullx", "1 2", "01", "-", "1.", "1e", "1e+"] {
    assert_true(@core.parse_json(input) is None)
  }
  assert_true(@core.parse_json(" true \n") is Some(_))
}

///|
test "JSON exponents retain magnitude" {
  let number = @core.parse_json("1.25e2").unwrap().as_number().unwrap()
  assert_eq(number, 125.0)
  let negative = @core.parse_json("-2e-2").unwrap().as_number().unwrap()
  assert_true(negative < -0.019 && negative > -0.021)
}

///|
test "JSON rejects unknown escapes and raw control characters" {
  assert_true(@core.parse_json("\"\\q\"") is None)
  assert_true(@core.parse_json("\"raw\nnewline\"") is None)
}

///|
test "JSON Unicode escapes support surrogate pairs" {
  assert_eq(
    @core.parse_json("\"\\u65e5\"").unwrap().as_string().unwrap(),
    "日",
  )
  assert_eq(
    @core.parse_json("\"\\ud83d\\ude00\"").unwrap().as_string().unwrap(),
    "😀",
  )
  for input in ["\"\\uZZZZ\"", "\"\\ud800\"", "\"\\udc00\""] {
    assert_true(@core.parse_json(input) is None)
  }
}
