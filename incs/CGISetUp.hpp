#pragma once
#include "Client.hpp"

// Builds CGI environment, args array, and spawns the child,
// stores CGIProcess object in the client so stdin and stdout can be registered with epoll
StatusCode setUpCGI(Client& client);
