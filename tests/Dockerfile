# Tiny MAVLink client used only by the smoke test (not part of the SITL image).
FROM python:3.12-slim
LABEL project=ardu-docker-minimal
RUN pip install --no-cache-dir pymavlink==2.4.43
ENV MAVLINK20=1 MAVLINK_DIALECT=ardupilotmega PYTHONUNBUFFERED=1
COPY smoke_test.py /smoke_test.py
ENTRYPOINT ["python3", "/smoke_test.py"]
