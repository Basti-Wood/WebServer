#pragma once
#include "CgiProcess.hpp"
#include "HTTPRequest.hpp"

// body's fully in by now, build the process and kick it off. Not spawned
// yet, that + epoll registration is still ahead.
StatusCode handleCGI(HTTPRequest& request, HTTPResponse& response,
					 const Config::Socket& socket);
