import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from publish_payments import make_event
from setup_aws import firehose_request, ident, names


class SetupAwsTests(unittest.TestCase):
    def test_names_are_scoped_to_prefix_account_region(self):
        n = names('sg-pay', '123456789012', 'us-west-2')
        self.assertEqual(n['bucket'], 'sg-pay-123456789012-us-west-2')
        self.assertEqual(n['storage_int'], 'SG_PAY_S3_INT')
        self.assertEqual(n['firehose_stream'], 'sg-pay-payments')

    def test_rejects_unsafe_identifiers(self):
        for bad in ['DB; DROP', 'a-b', '1abc', '']:
            with self.assertRaises(ValueError):
                ident(bad)

    def test_firehose_request_matches_aws_schema(self):
        import botocore.session
        from botocore.validate import validate_parameters
        n = names('sg-pay', '123456789012', 'us-west-2')
        req = firehose_request(n, n['bucket'], 'arn:aws:iam::123456789012:role/sg-pay-firehose-s3')
        model = botocore.session.get_session().get_service_model('firehose')
        validate_parameters(req, model.operation_model('CreateDeliveryStream').input_shape)
        dest = req['ExtendedS3DestinationConfiguration']
        self.assertEqual(dest['Prefix'], 'payments/')
        self.assertFalse(dest['ErrorOutputPrefix'].startswith('payments/'))

    def test_payment_event_matches_pipe_columns(self):
        import random
        event = make_event(random.Random(7))
        self.assertEqual(set(event), {'route_id', 'event_ts', 'amount_sgd', 'settle_seconds', 'status', 'sent_ms'})
        self.assertRegex(event['route_id'], r'^RTE-00[0-3]\d$')
        self.assertIn(event['status'], ('EXCEPTION', 'OK'))


if __name__ == '__main__':
    unittest.main()
