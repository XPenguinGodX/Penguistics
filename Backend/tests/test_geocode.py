"""Exercise GeocodeFunction with a fake Amazon Location client; never contact AWS."""
from pathlib import Path
import runpy
import sys
import types
import unittest
from unittest.mock import Mock, patch

BACKEND = Path(__file__).resolve().parents[1]


class FakeBotoCoreError(Exception):
    pass


class FakeClientError(Exception):
    pass


def place(locality="Salt Lake City", region="Utah"):
    """Shape of one Amazon Location ReverseGeocode result item."""
    address = {"Country": {"Code3": "USA"}}
    if locality is not None:
        address["Locality"] = locality
    if region is not None:
        address["Region"] = {"Code": "UT", "Name": region}
    return {"ResultItems": [{"Address": address}]}


class GeocodeTests(unittest.TestCase):
    def setUp(self):
        self.places = Mock()
        self.places.reverse_geocode.return_value = place()
        boto3 = types.ModuleType("boto3")
        boto3.client = Mock(return_value=self.places)
        errors = types.ModuleType("botocore.exceptions")
        errors.BotoCoreError = FakeBotoCoreError
        errors.ClientError = FakeClientError
        with patch.dict(sys.modules, {"boto3": boto3, "botocore": types.ModuleType("botocore"),
                                      "botocore.exceptions": errors}):
            self.handler = runpy.run_path(str(BACKEND / "scripts" / "geocode.py"))["handler"]
        boto3.client.assert_called_once_with("geo-places")

    def test_point_in_a_city_returns_city_and_state(self):
        result = self.handler({"lat": 40.76, "long": -111.89}, None)
        self.assertEqual(result, {"found": True, "city": "Salt Lake City", "state": "Utah"})

    def test_amazon_location_gets_longitude_first_and_storage_use(self):
        self.handler({"lat": 40.76, "long": -111.89}, None)
        kwargs = self.places.reverse_geocode.call_args.kwargs
        self.assertEqual(kwargs["QueryPosition"], [-111.89, 40.76])
        self.assertEqual(kwargs["IntendedUse"], "Storage")
        self.assertEqual(kwargs["MaxResults"], 1)

    def test_names_are_trimmed_and_inner_spaces_collapsed(self):
        self.places.reverse_geocode.return_value = place("  Salt   Lake City ", " Utah ")
        result = self.handler({"lat": 40.76, "long": -111.89}, None)
        self.assertEqual((result["city"], result["state"]), ("Salt Lake City", "Utah"))

    def test_towns_count_as_cities(self):
        self.places.reverse_geocode.return_value = place("Alta")
        self.assertEqual(self.handler({"lat": 40.59, "long": -111.64}, None)["city"], "Alta")

    def test_no_city_or_state_is_not_found(self):
        cases = {"ocean": {"ResultItems": []},
                 "no locality": place(locality=None),
                 "no region": place(region=None),
                 "blank locality": place(locality="   ")}
        for name, answer in cases.items():
            with self.subTest(name):
                self.places.reverse_geocode.return_value = answer
                self.assertEqual(self.handler({"lat": 0.0, "long": 0.0}, None),
                                 {"found": False, "city": None, "state": None})

    def test_invalid_coordinates_are_not_found_without_calling_aws(self):
        cases = {"missing": {}, "text": {"lat": "north", "long": 1},
                 "boolean": {"lat": True, "long": 1}, "out of range": {"lat": 91, "long": 1},
                 "not a dict": None}
        for name, event in cases.items():
            with self.subTest(name):
                self.assertFalse(self.handler(event, None)["found"])
        self.places.reverse_geocode.assert_not_called()

    def test_amazon_location_failure_raises_so_the_caller_can_retry(self):
        self.places.reverse_geocode.side_effect = FakeClientError()
        with self.assertRaises(FakeClientError):
            self.handler({"lat": 40.76, "long": -111.89}, None)


if __name__ == "__main__":
    unittest.main()
