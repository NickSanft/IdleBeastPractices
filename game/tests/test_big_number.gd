extends GutTest


func test_round_trip_via_dict():
	var b := BigNumber.from_float(1234.5)
	var d := b.to_dict()
	var b2 := BigNumber.from_dict(d)
	assert_almost_eq(b2.mantissa, b.mantissa, 1.0e-9)
	assert_eq(b2.exponent, b.exponent)


func test_add_mixed_exponents():
	var a := BigNumber.from_float(1000.0)
	var b := BigNumber.from_float(1.0)
	var sum := a.add(b)
	assert_almost_eq(sum.to_float(), 1001.0, 1.0e-6)


func test_add_huge_gap_returns_larger():
	var a := BigNumber.new()
	a.mantissa = 1.0
	a.exponent = 100
	var b := BigNumber.from_float(1.0)
	var sum := a.add(b)
	assert_eq(sum.exponent, 100)
	assert_almost_eq(sum.mantissa, 1.0, 1.0e-9)


func test_multiply_overflow_normalizes():
	var a := BigNumber.new()
	a.mantissa = 1.0
	a.exponent = 100
	var b := BigNumber.new()
	b.mantissa = 1.0
	b.exponent = 100
	var product := a.multiply(b)
	assert_eq(product.exponent, 200)
	assert_almost_eq(product.mantissa, 1.0, 1.0e-9)


func test_subtract_to_canonical_zero():
	var a := BigNumber.from_float(5.0)
	var b := BigNumber.from_float(5.0)
	var diff := a.subtract(b)
	assert_true(diff.is_zero(), "Expected zero result")
	assert_eq(diff.mantissa, 0.0)
	assert_eq(diff.exponent, 0)


func test_compare_branches():
	var zero := BigNumber.zero()
	var one := BigNumber.one()
	var two := BigNumber.from_float(2.0)
	var neg_one := BigNumber.from_float(-1.0)
	# zero vs nonzero
	assert_eq(zero.compare(one), -1)
	assert_eq(one.compare(zero), 1)
	# equal
	assert_eq(one.compare(BigNumber.one()), 0)
	# same sign, different value
	assert_eq(one.compare(two), -1)
	assert_eq(two.compare(one), 1)
	# different signs
	assert_eq(neg_one.compare(one), -1)
	assert_eq(one.compare(neg_one), 1)


func test_divide_by_zero_returns_zero():
	var a := BigNumber.from_float(10.0)
	var zero := BigNumber.zero()
	# push_error during the call is expected; assert the caller-visible behavior.
	var result := a.divide(zero)
	assert_true(result.is_zero(), "Divide by zero should yield zero")


func test_pow_int_zero_and_negative():
	var two := BigNumber.from_float(2.0)
	assert_almost_eq(two.pow_int(0).to_float(), 1.0, 1.0e-9)
	# 2^-2 = 0.25
	var quarter := two.pow_int(-2)
	assert_almost_eq(quarter.to_float(), 0.25, 1.0e-9)
	# 2^10 = 1024
	assert_almost_eq(two.pow_int(10).to_float(), 1024.0, 1.0e-6)


func test_format_basic_and_named_suffixes():
	assert_eq(BigNumber.zero().format(), "0")
	assert_eq(BigNumber.from_float(42.0).format(), "42")
	assert_eq(BigNumber.from_float(999.0).format(), "999")
	assert_eq(BigNumber.from_float(1000.0).format(), "1.00K")
	assert_eq(BigNumber.from_float(1234.0).format(), "1.23K")
	assert_eq(BigNumber.from_float(1500000.0).format(), "1.50M")


func test_format_letter_pair_suffixes():
	# 1.0e36 = "1.00aa"
	var aa := BigNumber.new()
	aa.mantissa = 1.0
	aa.exponent = 36
	assert_eq(aa.format(), "1.00aa")
	# 1.23e39 = "1.23ab"
	var ab := BigNumber.new()
	ab.mantissa = 1.23
	ab.exponent = 39
	assert_eq(ab.format(), "1.23ab")
