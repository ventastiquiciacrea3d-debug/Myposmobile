<?php

namespace Firebase\JWT;

// Esta interfaz es necesaria para las clases de excepción personalizadas.
interface JWTExceptionWithPayloadInterface
{
    public function setPayload(object $payload): void;
    public function getPayload(): object;
}