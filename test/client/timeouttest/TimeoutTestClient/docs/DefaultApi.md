# DefaultApi

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**delayresponse_get**](DefaultApi.md#delayresponse_get) | **GET** /delayresponse | Delay Response Endpoint
[**longpollstream_get**](DefaultApi.md#longpollstream_get) | **GET** /longpollstream | Long polled streaming endpoint


# **delayresponse_get**
> delayresponse_get(_api::DefaultApi, delay_seconds::Int64; _mediaType=nothing) -> DelayresponseGet200Response, OpenAPI.Clients.ApiResponse <br/>
> delayresponse_get(_api::DefaultApi, response_stream::Channel, delay_seconds::Int64; _mediaType=nothing) -> Channel{ DelayresponseGet200Response }, OpenAPI.Clients.ApiResponse

Delay Response Endpoint

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **DefaultApi** | API context | 
**delay_seconds** | **Int64** | Number of seconds to delay the response |

### Return type

[**DelayresponseGet200Response**](DelayresponseGet200Response.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)

# **longpollstream_get**
> longpollstream_get(_api::DefaultApi, delay_seconds::Int64; _mediaType=nothing) -> DelayresponseGet200Response, OpenAPI.Clients.ApiResponse <br/>
> longpollstream_get(_api::DefaultApi, response_stream::Channel, delay_seconds::Int64; _mediaType=nothing) -> Channel{ DelayresponseGet200Response }, OpenAPI.Clients.ApiResponse

Long polled streaming endpoint

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **DefaultApi** | API context | 
**delay_seconds** | **Int64** | Number of seconds to delay the response |

### Return type

[**DelayresponseGet200Response**](DelayresponseGet200Response.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)

