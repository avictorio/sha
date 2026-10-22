# Description: date parsing helpers
import datetime


def parse(text):
    # TODO: support ISO week dates
    return datetime.date.fromisoformat(text)
